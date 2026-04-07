import nodemailer from 'nodemailer';
import { logger } from '../utils/logger';

const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: parseInt(process.env.SMTP_PORT || '587'),
  secure: process.env.SMTP_PORT === '465',
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASSWORD,
  },
});

class EmailService {
  private from = `"${process.env.SMTP_FROM_NAME || 'LondonSnaps'}" <${process.env.SMTP_FROM || 'noreply@londonsnaps.app'}>`;

  async sendVerificationEmail(email: string, code: string): Promise<void> {
    try {
      await transporter.sendMail({
        from: this.from,
        to: email,
        subject: 'Verify your LondonSnaps account',
        html: `
          <!DOCTYPE html>
          <html>
          <head>
            <style>
              body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
              .container { max-width: 600px; margin: 0 auto; padding: 40px 20px; }
              .header { text-align: center; margin-bottom: 40px; }
              .logo { font-size: 32px; font-weight: bold; color: #6366F1; }
              .code { font-size: 36px; font-weight: bold; letter-spacing: 8px; color: #1F2937; 
                      background: #F3F4F6; padding: 20px; border-radius: 12px; text-align: center; }
              .footer { text-align: center; margin-top: 40px; color: #6B7280; font-size: 14px; }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="header">
                <div class="logo">LondonSnaps</div>
              </div>
              <h2>Verify your email</h2>
              <p>Thanks for signing up! Use this code to verify your email address:</p>
              <div class="code">${code}</div>
              <p>This code expires in 1 hour.</p>
              <p>If you didn't create an account, you can safely ignore this email.</p>
              <div class="footer">
                <p>&copy; ${new Date().getFullYear()} LondonSnaps. All rights reserved.</p>
              </div>
            </div>
          </body>
          </html>
        `,
      });
      logger.info(`Verification email sent to ${email}`);
    } catch (error) {
      logger.error('Failed to send verification email:', error);
      throw error;
    }
  }

  async sendUniversityVerification(email: string, code: string): Promise<void> {
    try {
      await transporter.sendMail({
        from: this.from,
        to: email,
        subject: 'Verify your university email - LondonSnaps',
        html: `
          <!DOCTYPE html>
          <html>
          <head>
            <style>
              body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
              .container { max-width: 600px; margin: 0 auto; padding: 40px 20px; }
              .header { text-align: center; margin-bottom: 40px; }
              .logo { font-size: 32px; font-weight: bold; color: #6366F1; }
              .badge { display: inline-block; background: #10B981; color: white; 
                       padding: 4px 12px; border-radius: 9999px; font-size: 14px; }
              .code { font-size: 36px; font-weight: bold; letter-spacing: 8px; color: #1F2937; 
                      background: #F3F4F6; padding: 20px; border-radius: 12px; text-align: center; }
              .footer { text-align: center; margin-top: 40px; color: #6B7280; font-size: 14px; }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="header">
                <div class="logo">LondonSnaps</div>
              </div>
              <h2>Verify your university email <span class="badge">Student</span></h2>
              <p>You're one step away from becoming a verified student on LondonSnaps!</p>
              <p>Use this code to verify your university email:</p>
              <div class="code">${code}</div>
              <p>This code expires in 24 hours.</p>
              <p>Once verified, you'll get access to exclusive student features including university circles, student events, and study buddy matching.</p>
              <div class="footer">
                <p>&copy; ${new Date().getFullYear()} LondonSnaps. All rights reserved.</p>
              </div>
            </div>
          </body>
          </html>
        `,
      });
      logger.info(`University verification email sent to ${email}`);
    } catch (error) {
      logger.error('Failed to send university verification email:', error);
      throw error;
    }
  }

  async sendPasswordResetEmail(email: string, code: string): Promise<void> {
    try {
      await transporter.sendMail({
        from: this.from,
        to: email,
        subject: 'Reset your LondonSnaps password',
        html: `
          <!DOCTYPE html>
          <html>
          <head>
            <style>
              body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
              .container { max-width: 600px; margin: 0 auto; padding: 40px 20px; }
              .header { text-align: center; margin-bottom: 40px; }
              .logo { font-size: 32px; font-weight: bold; color: #6366F1; }
              .code { font-size: 36px; font-weight: bold; letter-spacing: 8px; color: #1F2937; 
                      background: #F3F4F6; padding: 20px; border-radius: 12px; text-align: center; }
              .footer { text-align: center; margin-top: 40px; color: #6B7280; font-size: 14px; }
              .warning { background: #FEF2F2; border: 1px solid #FCA5A5; padding: 15px; 
                         border-radius: 8px; color: #991B1B; }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="header">
                <div class="logo">LondonSnaps</div>
              </div>
              <h2>Reset your password</h2>
              <p>We received a request to reset your password. Use this code:</p>
              <div class="code">${code}</div>
              <p>This code expires in 1 hour.</p>
              <div class="warning">
                <strong>Didn't request this?</strong> If you didn't request a password reset, 
                please ignore this email and ensure your account is secure.
              </div>
              <div class="footer">
                <p>&copy; ${new Date().getFullYear()} LondonSnaps. All rights reserved.</p>
              </div>
            </div>
          </body>
          </html>
        `,
      });
      logger.info(`Password reset email sent to ${email}`);
    } catch (error) {
      logger.error('Failed to send password reset email:', error);
      throw error;
    }
  }

  async sendOTPEmail(email: string, code: string): Promise<void> {
    try {
      await transporter.sendMail({
        from: this.from,
        to: email,
        subject: 'Your LondonSnaps verification code',
        html: `
          <!DOCTYPE html>
          <html>
          <head>
            <style>
              body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
              .container { max-width: 600px; margin: 0 auto; padding: 40px 20px; }
              .header { text-align: center; margin-bottom: 40px; }
              .logo { font-size: 32px; font-weight: bold; color: #6366F1; }
              .code { font-size: 36px; font-weight: bold; letter-spacing: 8px; color: #1F2937; 
                      background: #F3F4F6; padding: 20px; border-radius: 12px; text-align: center; }
              .footer { text-align: center; margin-top: 40px; color: #6B7280; font-size: 14px; }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="header">
                <div class="logo">LondonSnaps</div>
              </div>
              <h2>Verification Code</h2>
              <p>Use this code to verify your account:</p>
              <div class="code">${code}</div>
              <p>This code expires in 5 minutes.</p>
              <p>If you didn't request this, you can safely ignore this email.</p>
              <div class="footer">
                <p>&copy; ${new Date().getFullYear()} LondonSnaps. All rights reserved.</p>
              </div>
            </div>
          </body>
          </html>
        `,
      });
      logger.info(`OTP email sent to ${email}`);
    } catch (error) {
      logger.error('Failed to send OTP email:', error);
      throw error;
    }
  }

  async sendWelcomeEmail(email: string, displayName: string): Promise<void> {
    try {
      await transporter.sendMail({
        from: this.from,
        to: email,
        subject: 'Welcome to LondonSnaps! 🎉',
        html: `
          <!DOCTYPE html>
          <html>
          <head>
            <style>
              body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
              .container { max-width: 600px; margin: 0 auto; padding: 40px 20px; }
              .header { text-align: center; margin-bottom: 40px; }
              .logo { font-size: 32px; font-weight: bold; color: #6366F1; }
              .feature { display: flex; align-items: center; margin: 20px 0; }
              .feature-icon { font-size: 24px; margin-right: 15px; }
              .footer { text-align: center; margin-top: 40px; color: #6B7280; font-size: 14px; }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="header">
                <div class="logo">LondonSnaps</div>
              </div>
              <h2>Welcome, ${displayName}! 🎉</h2>
              <p>You've joined the best way for London students to connect. Here's what you can do:</p>
              
              <div class="feature">
                <span class="feature-icon">📸</span>
                <div>
                  <strong>Send Snaps</strong>
                  <p>Share moments with friends that disappear after viewing</p>
                </div>
              </div>
              
              <div class="feature">
                <span class="feature-icon">📖</span>
                <div>
                  <strong>Post Stories</strong>
                  <p>Share your day with all your friends</p>
                </div>
              </div>
              
              <div class="feature">
                <span class="feature-icon">🎓</span>
                <div>
                  <strong>Join University Circles</strong>
                  <p>Connect with students from your course, halls, and societies</p>
                </div>
              </div>
              
              <div class="feature">
                <span class="feature-icon">🎉</span>
                <div>
                  <strong>Discover Events</strong>
                  <p>Find and join student events across London</p>
                </div>
              </div>
              
              <p>Start by adding friends and setting up your profile!</p>
              
              <div class="footer">
                <p>&copy; ${new Date().getFullYear()} LondonSnaps. All rights reserved.</p>
              </div>
            </div>
          </body>
          </html>
        `,
      });
      logger.info(`Welcome email sent to ${email}`);
    } catch (error) {
      logger.error('Failed to send welcome email:', error);
      // Don't throw - welcome email is not critical
    }
  }
}

export const emailService = new EmailService();
