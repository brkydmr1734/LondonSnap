import { logger } from '../utils/logger';
import { emailService } from './email.service';

class SMSService {
  // OTP is now sent via email instead of SMS
  async sendOTP(phone: string, code: string, email?: string): Promise<void> {
    if (email) {
      try {
        await emailService.sendOTPEmail(email, code);
        logger.info(`OTP sent to email ${email} (for phone ${phone})`);
      } catch (error) {
        logger.error('Failed to send OTP email:', error);
        logger.info(`[DEV] OTP for ${phone}: ${code}`);
      }
    } else {
      // No email provided, log OTP for development
      logger.warn(`SMS disabled - OTP for ${phone}: ${code}`);
    }
  }

  async sendStreakReminder(_phone: string, _friendName: string, _hoursLeft: number): Promise<void> {
    // Streak reminders are sent via push notifications, not SMS
    logger.info('Streak reminders are handled via push notifications');
  }

  async sendSecurityAlert(_phone: string, _message: string): Promise<void> {
    // Security alerts are logged only
    logger.info('Security alerts are handled via push notifications');
  }
}

export const smsService = new SMSService();
