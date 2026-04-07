import { Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { authService } from '../services/auth.service';
import { BadRequestError } from '../../common/utils/AppError';

// Validation schemas
const registerSchema = z.object({
  email: z.string().email('Invalid email address'),
  username: z.string()
    .min(3, 'Username must be at least 3 characters')
    .max(20, 'Username must be at most 20 characters')
    .regex(/^[a-zA-Z0-9_]+$/, 'Username can only contain letters, numbers, and underscores'),
  displayName: z.string().min(1, 'Display name is required').max(50),
  password: z.string()
    .min(8, 'Password must be at least 8 characters')
    .regex(/[A-Z]/, 'Password must contain at least one uppercase letter')
    .regex(/[a-z]/, 'Password must contain at least one lowercase letter')
    .regex(/[0-9]/, 'Password must contain at least one number'),
  birthday: z.string().optional(),
  gender: z.enum(['MALE', 'FEMALE', 'NON_BINARY', 'PREFER_NOT_TO_SAY']).optional(),
  deviceType: z.enum(['IOS', 'ANDROID', 'WEB']).optional(),
  deviceName: z.string().optional(),
  deviceId: z.string().optional(),
});

const loginSchema = z.object({
  email: z.string().email('Invalid email address'),
  password: z.string().min(1, 'Password is required'),
  deviceType: z.enum(['IOS', 'ANDROID', 'WEB']).optional(),
  deviceName: z.string().optional(),
  deviceId: z.string().optional(),
});

const socialAuthSchema = z.object({
  provider: z.enum(['APPLE', 'GOOGLE']),
  providerId: z.string().min(1, 'Provider ID is required'),
  email: z.string().email().optional(),
  displayName: z.string().optional(),
  avatarUrl: z.string().url().optional(),
  deviceType: z.enum(['IOS', 'ANDROID', 'WEB']).optional(),
  deviceName: z.string().optional(),
  deviceId: z.string().optional(),
});

export class AuthController {
  // Register
  async register(req: Request, res: Response, next: NextFunction) {
    try {
      const data = registerSchema.parse(req.body);
      const result = await authService.register(data);
      
      res.status(201).json({
        success: true,
        message: 'Registration successful. Please verify your email.',
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  // Login
  async login(req: Request, res: Response, next: NextFunction) {
    try {
      const data = loginSchema.parse(req.body);
      const result = await authService.login({
        ...data,
        ipAddress: req.ip,
        userAgent: req.headers['user-agent'],
      });
      
      res.json({
        success: true,
        message: 'Login successful',
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  // Social auth
  async socialAuth(req: Request, res: Response, next: NextFunction) {
    try {
      const data = socialAuthSchema.parse(req.body);
      const result = await authService.socialAuth(data);
      
      res.json({
        success: true,
        message: result.isNewUser ? 'Account created successfully' : 'Login successful',
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  // Request phone OTP
  async requestPhoneOTP(req: Request, res: Response, next: NextFunction) {
    try {
      const { phone } = req.body;
      
      if (!phone || !/^\+\d{10,15}$/.test(phone)) {
        throw new BadRequestError('Valid phone number required (e.g., +447123456789)');
      }
      
      const result = await authService.requestPhoneOTP(phone, req.user?.id);
      
      res.json({
        success: true,
        message: result.message,
      });
    } catch (error) {
      next(error);
    }
  }

  // Verify phone OTP
  async verifyPhoneOTP(req: Request, res: Response, next: NextFunction) {
    try {
      const { phone, code } = req.body;
      
      if (!phone || !code) {
        throw new BadRequestError('Phone and code are required');
      }
      
      const result = await authService.verifyPhoneOTP({ phone, code });
      
      res.json({
        success: true,
        message: 'Phone verified successfully',
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  // Verify email
  async verifyEmail(req: Request, res: Response, next: NextFunction) {
    try {
      const { code } = req.body;
      
      if (!code || !req.user) {
        throw new BadRequestError('Verification code required');
      }
      
      const result = await authService.verifyEmail(req.user.id, code);
      
      res.json({
        success: true,
        message: 'Email verified successfully',
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  // Verify university email
  async verifyUniversityEmail(req: Request, res: Response, next: NextFunction) {
    try {
      const { universityEmail } = req.body;
      
      if (!universityEmail || !req.user) {
        throw new BadRequestError('University email required');
      }
      
      const result = await authService.verifyUniversityEmail(req.user.id, universityEmail);
      
      res.json({
        success: true,
        message: result.message,
        data: { university: result.university },
      });
    } catch (error) {
      next(error);
    }
  }

  // Complete university verification
  async completeUniversityVerification(req: Request, res: Response, next: NextFunction) {
    try {
      const { code } = req.body;
      
      if (!code || !req.user) {
        throw new BadRequestError('Verification code required');
      }
      
      const result = await authService.completeUniversityVerification(req.user.id, code);
      
      res.json({
        success: true,
        message: 'University verified successfully',
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  // Refresh token
  async refreshToken(req: Request, res: Response, next: NextFunction) {
    try {
      const { refreshToken } = req.body;
      
      if (!refreshToken) {
        throw new BadRequestError('Refresh token required');
      }
      
      const result = await authService.refreshToken(refreshToken);
      
      res.json({
        success: true,
        message: 'Token refreshed',
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  // Logout
  async logout(req: Request, res: Response, next: NextFunction) {
    try {
      if (req.token) {
        await authService.logout(req.token);
      }
      
      res.json({
        success: true,
        message: 'Logged out successfully',
      });
    } catch (error) {
      next(error);
    }
  }

  // Logout all devices
  async logoutAll(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }
      
      await authService.logoutAll(req.user.id);
      
      res.json({
        success: true,
        message: 'Logged out from all devices',
      });
    } catch (error) {
      next(error);
    }
  }

  // Change password (authenticated)
  async changePassword(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const { currentPassword, newPassword } = req.body;

      if (!currentPassword || !newPassword) {
        throw new BadRequestError('Current password and new password are required');
      }

      // Validate new password
      const passwordSchema = z.string()
        .min(8, 'Password must be at least 8 characters')
        .regex(/[A-Z]/, 'Password must contain at least one uppercase letter')
        .regex(/[a-z]/, 'Password must contain at least one lowercase letter')
        .regex(/[0-9]/, 'Password must contain at least one number');

      passwordSchema.parse(newPassword);

      const result = await authService.changePassword(req.user.id, currentPassword, newPassword);

      res.json({
        success: true,
        message: result.message,
      });
    } catch (error) {
      next(error);
    }
  }

  // Request password reset
  async requestPasswordReset(req: Request, res: Response, next: NextFunction) {
    try {
      const { email } = req.body;
      
      if (!email) {
        throw new BadRequestError('Email required');
      }
      
      const result = await authService.requestPasswordReset(email);
      
      res.json({
        success: true,
        message: result.message,
      });
    } catch (error) {
      next(error);
    }
  }

  // Reset password
  async resetPassword(req: Request, res: Response, next: NextFunction) {
    try {
      const { email, code, newPassword } = req.body;
      
      if (!email || !code || !newPassword) {
        throw new BadRequestError('Email, code, and new password are required');
      }
      
      // Validate new password
      const passwordSchema = z.string()
        .min(8, 'Password must be at least 8 characters')
        .regex(/[A-Z]/, 'Password must contain at least one uppercase letter')
        .regex(/[a-z]/, 'Password must contain at least one lowercase letter')
        .regex(/[0-9]/, 'Password must contain at least one number');
      
      passwordSchema.parse(newPassword);
      
      const result = await authService.resetPassword(email, code, newPassword);
      
      res.json({
        success: true,
        message: result.message,
      });
    } catch (error) {
      next(error);
    }
  }

  // Delete account
  async deleteAccount(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }
      
      const { password } = req.body;
      
      const result = await authService.deleteAccount(req.user.id, password);
      
      res.json({
        success: true,
        message: result.message,
      });
    } catch (error) {
      next(error);
    }
  }

  // Get current user
  async getCurrentUser(req: Request, res: Response, next: NextFunction) {
    try {
      res.json({
        success: true,
        data: { user: req.user },
      });
    } catch (error) {
      next(error);
    }
  }
}

export const authController = new AuthController();
