import { Router } from 'express';
import { authController } from '../controllers/auth.controller';
import { authMiddleware, optionalAuthMiddleware } from '../middleware/auth.middleware';

const router = Router();

// Public routes
router.post('/register', authController.register);
router.post('/login', authController.login);
router.post('/social', authController.socialAuth);
router.post('/refresh', authController.refreshToken);
router.post('/password/reset-request', authController.requestPasswordReset);
router.post('/password/reset', authController.resetPassword);

// Phone OTP (can be used for both signup and linking)
router.post('/phone/request-otp', optionalAuthMiddleware, authController.requestPhoneOTP);
router.post('/phone/verify', optionalAuthMiddleware, authController.verifyPhoneOTP);

// Protected routes
router.post('/verify-email', authMiddleware, authController.verifyEmail);
router.post('/verify-university', authMiddleware, authController.verifyUniversityEmail);
router.post('/verify-university/complete', authMiddleware, authController.completeUniversityVerification);
router.post('/logout', authMiddleware, authController.logout);
router.post('/logout-all', authMiddleware, authController.logoutAll);
router.post('/password/change', authMiddleware, authController.changePassword);
router.delete('/account', authMiddleware, authController.deleteAccount);
router.get('/me', authMiddleware, authController.getCurrentUser);

export default router;
