import { Gender, DeviceType } from '@prisma/client';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

export interface RegisterDTO {
  email: string;
  username: string;
  displayName: string;
  password: string;
  birthday?: string;
  gender?: Gender;
  deviceType?: DeviceType;
  deviceName?: string;
  deviceId?: string;
}

export interface LoginDTO {
  email: string;
  password: string;
  deviceType?: DeviceType;
  deviceName?: string;
  deviceId?: string;
  ipAddress?: string;
  userAgent?: string;
}

export interface SocialAuthDTO {
  provider: 'APPLE' | 'GOOGLE';
  providerId: string;
  email?: string;
  displayName?: string;
  avatarUrl?: string;
  deviceType?: DeviceType;
  deviceName?: string;
  deviceId?: string;
}

export interface PhoneVerifyDTO {
  phone: string;
  code: string;
}

export interface AuthenticatedUser {
  id: string;
  email: string;
  username: string;
  displayName: string;
  avatarUrl: string | null;
  isVerified: boolean;
  isUniversityStudent: boolean;
  universityId: string | null;
  university?: {
    id: string;
    name: string;
    shortName: string;
    domain: string;
    logoUrl: string | null;
  } | null;
}

export interface JWTPayload {
  userId: string;
  type: 'access' | 'refresh';
  iat: number;
  exp: number;
}
