import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import dayjs from 'dayjs';
import { prisma } from '../../index';
import { 
  BadRequestError, 
  UnauthorizedError, 
  ConflictError, 
  NotFoundError 
} from '../../common/utils/AppError';
import { emailService } from '../../common/services/email.service';
import { authCache } from '../../common/utils/cache';
import { smsService } from '../../common/services/sms.service';
import { 
  RegisterDTO, 
  LoginDTO, 
  SocialAuthDTO, 
  PhoneVerifyDTO,
  TokenPair 
} from '../models/auth.types';

const JWT_SECRET = process.env.JWT_SECRET!;
const JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || process.env.JWT_SECRET!;
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '7d';
const JWT_REFRESH_EXPIRES_IN = process.env.JWT_REFRESH_EXPIRES_IN || '30d';

export class AuthService {
  
  // Generate JWT tokens
  private generateTokens(userId: string): TokenPair {
    const accessToken = jwt.sign(
      { userId, type: 'access', jti: uuidv4() },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRES_IN as any }
    );

    const refreshToken = jwt.sign(
      { userId, type: 'refresh', jti: uuidv4() },
      JWT_REFRESH_SECRET,
      { expiresIn: JWT_REFRESH_EXPIRES_IN as any }
    );

    return { accessToken, refreshToken };
  }

  // Calculate token expiry date
  private getTokenExpiry(expiresIn: string): Date {
    const match = expiresIn.match(/^(\d+)([dhms])$/);
    if (!match) return dayjs().add(7, 'day').toDate();

    const [, value, unit] = match;
    const unitMap: Record<string, dayjs.ManipulateType> = {
      'd': 'day',
      'h': 'hour',
      'm': 'minute',
      's': 'second',
    };

    return dayjs().add(parseInt(value), unitMap[unit]).toDate();
  }

  // Register with email/password
  async register(data: RegisterDTO) {
    // Check if email exists
    const existingEmail = await prisma.user.findUnique({
      where: { email: data.email.toLowerCase() },
    });
    if (existingEmail) {
      throw new ConflictError('Email already registered');
    }

    // Check if username exists
    const existingUsername = await prisma.user.findUnique({
      where: { username: data.username.toLowerCase() },
    });
    if (existingUsername) {
      throw new ConflictError('Username already taken');
    }

    // Hash password
    const passwordHash = await bcrypt.hash(data.password, 10);

    // Create user
    const user = await prisma.user.create({
      data: {
        email: data.email.toLowerCase(),
        username: data.username.toLowerCase(),
        displayName: data.displayName,
        passwordHash,
        birthday: data.birthday ? new Date(data.birthday) : null,
        gender: data.gender,
        privacySettings: {
          create: {},
        },
        notificationPrefs: {
          create: {},
        },
      },
      select: {
        id: true,
        email: true,
        username: true,
        displayName: true,
        avatarUrl: true,
        avatarConfig: true,
        isVerified: true,
        emailVerified: true,
        createdAt: true,
      },
    });

    // Generate verification code
    const verificationCode = Math.floor(100000 + Math.random() * 900000).toString();
    
    await prisma.verificationCode.create({
      data: {
        userId: user.id,
        email: user.email,
        code: verificationCode,
        type: 'EMAIL',
        expiresAt: dayjs().add(1, 'hour').toDate(),
      },
    });

    // Send verification email (non-blocking, don't fail registration if email fails)
    try {
      await emailService.sendVerificationEmail(user.email, verificationCode);
    } catch (emailErr) {
      console.warn('Failed to send verification email (non-fatal):', (emailErr as Error).message);
    }

    // Generate tokens
    const tokens = this.generateTokens(user.id);

    // Create session
    await prisma.session.create({
      data: {
        userId: user.id,
        token: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        deviceType: data.deviceType || 'IOS',
        deviceName: data.deviceName,
        deviceId: data.deviceId,
        expiresAt: this.getTokenExpiry(JWT_REFRESH_EXPIRES_IN),
      },
    });

    return {
      user,
      ...tokens,
    };
  }

  // Login with email/password
  async login(data: LoginDTO) {
    const user = await prisma.user.findUnique({
      where: { email: data.email.toLowerCase() },
      select: {
        id: true,
        email: true,
        username: true,
        displayName: true,
        avatarUrl: true,
        avatarConfig: true,
        passwordHash: true,
        isVerified: true,
        emailVerified: true,
        status: true,
        suspendedUntil: true,
      },
    });

    if (!user || !user.passwordHash) {
      throw new UnauthorizedError('Invalid email or password');
    }

    if (user.status === 'SUSPENDED') {
      if (user.suspendedUntil && dayjs().isBefore(user.suspendedUntil)) {
        throw new UnauthorizedError(
          `Account suspended until ${dayjs(user.suspendedUntil).format('MMMM D, YYYY')}`
        );
      }
    }

    if (user.status === 'DELETED' || user.status === 'DEACTIVATED') {
      throw new UnauthorizedError('Account is no longer active');
    }

    const isValidPassword = await bcrypt.compare(data.password, user.passwordHash);
    if (!isValidPassword) {
      throw new UnauthorizedError('Invalid email or password');
    }

    // Generate tokens
    const tokens = this.generateTokens(user.id);

    // Create session + update last seen in parallel
    await Promise.all([
      prisma.session.create({
        data: {
          userId: user.id,
          token: tokens.accessToken,
          refreshToken: tokens.refreshToken,
          deviceType: data.deviceType || 'IOS',
          deviceName: data.deviceName,
          deviceId: data.deviceId,
          ipAddress: data.ipAddress,
          userAgent: data.userAgent,
          expiresAt: this.getTokenExpiry(JWT_REFRESH_EXPIRES_IN),
        },
      }),
      prisma.user.update({
        where: { id: user.id },
        data: { 
          lastSeenAt: new Date(),
          isOnline: true,
        },
      }),
    ]);

    const { passwordHash, ...userWithoutPassword } = user;

    return {
      user: userWithoutPassword,
      ...tokens,
    };
  }

  // Social authentication (Apple/Google)
  async socialAuth(data: SocialAuthDTO) {
    let user;

    if (data.provider === 'APPLE') {
      user = await prisma.user.findUnique({
        where: { appleId: data.providerId },
      });
    } else if (data.provider === 'GOOGLE') {
      user = await prisma.user.findUnique({
        where: { googleId: data.providerId },
      });
    }

    // Check if email exists (for linking accounts)
    if (!user && data.email) {
      user = await prisma.user.findUnique({
        where: { email: data.email.toLowerCase() },
      });

      // Link social account to existing user
      if (user) {
        const updateData = data.provider === 'APPLE' 
          ? { appleId: data.providerId }
          : { googleId: data.providerId };
        
        user = await prisma.user.update({
          where: { id: user.id },
          data: updateData,
        });
      }
    }

    // Create new user if doesn't exist
    if (!user) {
      const username = await this.generateUniqueUsername(
        data.displayName || data.email?.split('@')[0] || 'user'
      );

      user = await prisma.user.create({
        data: {
          email: data.email?.toLowerCase() || `${data.providerId}@${data.provider.toLowerCase()}.local`,
          username,
          displayName: data.displayName || username,
          avatarUrl: data.avatarUrl,
          emailVerified: !!data.email, // Trust email from social providers
          ...(data.provider === 'APPLE' && { appleId: data.providerId }),
          ...(data.provider === 'GOOGLE' && { googleId: data.providerId }),
          privacySettings: {
            create: {},
          },
          notificationPrefs: {
            create: {},
          },
        },
      });
    }

    // Generate tokens
    const tokens = this.generateTokens(user.id);

    // Create session + update last seen in parallel
    await Promise.all([
      prisma.session.create({
        data: {
          userId: user.id,
          token: tokens.accessToken,
          refreshToken: tokens.refreshToken,
          deviceType: data.deviceType || 'IOS',
          deviceName: data.deviceName,
          deviceId: data.deviceId,
          expiresAt: this.getTokenExpiry(JWT_REFRESH_EXPIRES_IN),
        },
      }),
      prisma.user.update({
        where: { id: user.id },
        data: { 
          lastSeenAt: new Date(),
          isOnline: true,
        },
      }),
    ]);

    const { passwordHash, ...userWithoutPassword } = user;

    return {
      user: userWithoutPassword,
      ...tokens,
      isNewUser: !user.createdAt || dayjs().diff(user.createdAt, 'minute') < 1,
    };
  }

  // Request phone OTP (sent via email)
  async requestPhoneOTP(phone: string, userId?: string) {
    // Generate OTP
    const otp = Math.floor(100000 + Math.random() * 900000).toString();

    // Store verification code
    await prisma.verificationCode.create({
      data: {
        userId,
        phone,
        code: otp,
        type: 'PHONE',
        expiresAt: dayjs().add(5, 'minute').toDate(),
      },
    });

    // Get user's email to send OTP via email
    let userEmail: string | undefined;
    if (userId) {
      const user = await prisma.user.findUnique({ where: { id: userId }, select: { email: true } });
      userEmail = user?.email;
    }

    // Send OTP via email (or log in dev)
    try {
      await smsService.sendOTP(phone, otp, userEmail);
    } catch (smsErr) {
      console.warn('Failed to send OTP (non-fatal):', (smsErr as Error).message);
    }

    return { success: true, message: 'OTP sent successfully' };
  }

  // Verify phone OTP
  async verifyPhoneOTP(data: PhoneVerifyDTO) {
    const verification = await prisma.verificationCode.findFirst({
      where: {
        phone: data.phone,
        code: data.code,
        type: 'PHONE',
        usedAt: null,
        expiresAt: { gt: new Date() },
      },
      orderBy: { createdAt: 'desc' },
    });

    if (!verification) {
      throw new BadRequestError('Invalid or expired OTP');
    }

    // Mark as used
    await prisma.verificationCode.update({
      where: { id: verification.id },
      data: { usedAt: new Date() },
    });

    if (verification.userId) {
      // Update user phone verification
      await prisma.user.update({
        where: { id: verification.userId },
        data: {
          phone: data.phone,
          phoneVerified: true,
        },
      });
    }

    return { success: true, verified: true };
  }

  // Verify email
  async verifyEmail(userId: string, code: string) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
    });

    if (!user) {
      throw new NotFoundError('User not found');
    }

    const verification = await prisma.verificationCode.findFirst({
      where: {
        userId,
        code,
        type: 'EMAIL',
        usedAt: null,
        expiresAt: { gt: new Date() },
      },
      orderBy: { createdAt: 'desc' },
    });

    if (!verification) {
      throw new BadRequestError('Invalid or expired verification code');
    }

    // Mark as used and verify user
    await prisma.$transaction([
      prisma.verificationCode.update({
        where: { id: verification.id },
        data: { usedAt: new Date() },
      }),
      prisma.user.update({
        where: { id: userId },
        data: { emailVerified: true },
      }),
    ]);

    return { success: true, verified: true };
  }

  // Verify university email (.ac.uk)
  async verifyUniversityEmail(userId: string, universityEmail: string) {
    // Check if it's a valid UK university email
    if (!universityEmail.endsWith('.ac.uk')) {
      throw new BadRequestError('Please use a valid UK university email (.ac.uk)');
    }

    // Find university by domain
    const domain = universityEmail.split('@')[1];
    const university = await prisma.university.findUnique({
      where: { domain },
    });

    // Generate verification code
    const code = Math.floor(100000 + Math.random() * 900000).toString();

    await prisma.verificationCode.create({
      data: {
        userId,
        email: universityEmail,
        code,
        type: 'UNIVERSITY',
        expiresAt: dayjs().add(24, 'hour').toDate(),
      },
    });

    // Send verification email
    await emailService.sendUniversityVerification(universityEmail, code);

    return { 
      success: true, 
      message: 'Verification email sent to your university email',
      university: university?.name,
    };
  }

  // Complete university verification
  async completeUniversityVerification(userId: string, code: string) {
    const verification = await prisma.verificationCode.findFirst({
      where: {
        userId,
        code,
        type: 'UNIVERSITY',
        usedAt: null,
        expiresAt: { gt: new Date() },
      },
      orderBy: { createdAt: 'desc' },
    });

    if (!verification || !verification.email) {
      throw new BadRequestError('Invalid or expired verification code');
    }

    // Find or create university from email domain
    const domain = verification.email.split('@')[1];
    let university = await prisma.university.findUnique({
      where: { domain },
    });

    // Auto-create university if not in DB yet
    if (!university) {
      // Derive a readable name from the domain (e.g. westminster.ac.uk → Westminster)
      const namePart = domain.split('.')[0];
      const capitalized = namePart.charAt(0).toUpperCase() + namePart.slice(1);
      university = await prisma.university.create({
        data: {
          name: `University of ${capitalized}`,
          shortName: capitalized.toUpperCase(),
          domain,
          location: 'London, UK',
        },
      });
    }

    // Update user
    await prisma.$transaction([
      prisma.verificationCode.update({
        where: { id: verification.id },
        data: { usedAt: new Date() },
      }),
      prisma.user.update({
        where: { id: userId },
        data: {
          isUniversityStudent: true,
          isVerified: true,
          universityId: university.id,
        },
      }),
    ]);

    // Invalidate auth cache so next /auth/me returns fresh data with university
    authCache.invalidatePrefix(`user:${userId}`);

    return { 
      success: true, 
      verified: true,
      university: university.name,
    };
  }

  // Refresh token
  async refreshToken(refreshToken: string) {
    try {
      const decoded = jwt.verify(refreshToken, JWT_REFRESH_SECRET) as {
        userId: string;
        type: string;
      };

      if (decoded.type !== 'refresh') {
        throw new UnauthorizedError('Invalid token type');
      }

      // Find session
      const session = await prisma.session.findUnique({
        where: { refreshToken },
      });

      if (!session || session.expiresAt < new Date()) {
        throw new UnauthorizedError('Session expired');
      }

      // Generate new tokens
      const tokens = this.generateTokens(decoded.userId);

      // Update session
      await prisma.session.update({
        where: { id: session.id },
        data: {
          token: tokens.accessToken,
          refreshToken: tokens.refreshToken,
          expiresAt: this.getTokenExpiry(JWT_REFRESH_EXPIRES_IN),
          lastUsedAt: new Date(),
        },
      });

      return tokens;
    } catch (error) {
      throw new UnauthorizedError('Invalid refresh token');
    }
  }

  // Logout
  async logout(token: string) {
    await prisma.session.deleteMany({
      where: { token },
    });

    return { success: true };
  }

  // Logout all devices
  async logoutAll(userId: string) {
    await prisma.session.deleteMany({
      where: { userId },
    });

    await prisma.user.update({
      where: { id: userId },
      data: { isOnline: false },
    });

    return { success: true };
  }

  // Change password (authenticated user)
  async changePassword(userId: string, currentPassword: string, newPassword: string) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
    });

    if (!user) {
      throw new BadRequestError('User not found');
    }

    if (!user.passwordHash) {
      throw new BadRequestError('Account uses social login. Set a password via forgot password first.');
    }

    const isMatch = await bcrypt.compare(currentPassword, user.passwordHash);
    if (!isMatch) {
      throw new BadRequestError('Current password is incorrect');
    }

    const passwordHash = await bcrypt.hash(newPassword, 10);

    await prisma.user.update({
      where: { id: userId },
      data: { passwordHash },
    });

    return { success: true, message: 'Password changed successfully' };
  }

  // Request password reset
  async requestPasswordReset(email: string) {
    const user = await prisma.user.findUnique({
      where: { email: email.toLowerCase() },
    });

    if (!user) {
      // Don't reveal if user exists
      return { success: true, message: 'If account exists, reset email will be sent' };
    }

    const code = Math.floor(100000 + Math.random() * 900000).toString();

    await prisma.verificationCode.create({
      data: {
        userId: user.id,
        email: user.email,
        code,
        type: 'PASSWORD_RESET',
        expiresAt: dayjs().add(1, 'hour').toDate(),
      },
    });

    try {
      await emailService.sendPasswordResetEmail(user.email, code);
    } catch (emailErr) {
      console.warn('Failed to send password reset email (non-fatal):', (emailErr as Error).message);
    }

    return { success: true, message: 'If account exists, reset email will be sent' };
  }

  // Reset password
  async resetPassword(email: string, code: string, newPassword: string) {
    const verification = await prisma.verificationCode.findFirst({
      where: {
        email: email.toLowerCase(),
        code,
        type: 'PASSWORD_RESET',
        usedAt: null,
        expiresAt: { gt: new Date() },
      },
      orderBy: { createdAt: 'desc' },
    });

    if (!verification || !verification.userId) {
      throw new BadRequestError('Invalid or expired reset code');
    }

    const passwordHash = await bcrypt.hash(newPassword, 10);

    await prisma.$transaction([
      prisma.verificationCode.update({
        where: { id: verification.id },
        data: { usedAt: new Date() },
      }),
      prisma.user.update({
        where: { id: verification.userId },
        data: { passwordHash },
      }),
      // Invalidate all sessions
      prisma.session.deleteMany({
        where: { userId: verification.userId },
      }),
    ]);

    return { success: true, message: 'Password reset successfully' };
  }

  // Delete account
  async deleteAccount(userId: string, password?: string) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
    });

    if (!user) {
      throw new NotFoundError('User not found');
    }

    // Verify password if account has one
    if (user.passwordHash && password) {
      const isValid = await bcrypt.compare(password, user.passwordHash);
      if (!isValid) {
        throw new UnauthorizedError('Invalid password');
      }
    }

    // Soft delete - mark account as deleted
    await prisma.user.update({
      where: { id: userId },
      data: {
        status: 'DELETED',
        deletedAt: new Date(),
        email: `deleted_${userId}@deleted.local`,
        username: `deleted_${userId}`,
        phone: null,
        appleId: null,
        googleId: null,
      },
    });

    // Delete sessions
    await prisma.session.deleteMany({
      where: { userId },
    });

    return { success: true, message: 'Account deleted successfully' };
  }

  // Helper: Generate unique username
  private async generateUniqueUsername(base: string): Promise<string> {
    const sanitized = base.toLowerCase().replace(/[^a-z0-9]/g, '');
    let username = sanitized.slice(0, 15);
    let suffix = 0;

    while (true) {
      const exists = await prisma.user.findUnique({
        where: { username: suffix > 0 ? `${username}${suffix}` : username },
      });

      if (!exists) {
        return suffix > 0 ? `${username}${suffix}` : username;
      }

      suffix++;
    }
  }
}

export const authService = new AuthService();
