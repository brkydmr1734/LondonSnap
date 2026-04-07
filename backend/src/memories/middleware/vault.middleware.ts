import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { UnauthorizedError, ForbiddenError } from '../../common/utils/AppError';

const JWT_SECRET = process.env.JWT_SECRET || 'secret';

interface VaultTokenPayload {
  userId: string;
  type: 'vault_access';
}

/**
 * Middleware to verify vault access token for My Eyes Only protected routes
 * Requires the x-vault-token header with a valid vault access token
 */
export const requireVaultAccess = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    const vaultToken = req.headers['x-vault-token'] as string;

    if (!vaultToken) {
      return res.status(401).json({
        success: false,
        message: 'Vault token required',
      });
    }

    if (!req.user) {
      throw new UnauthorizedError('Authentication required');
    }

    try {
      const decoded = jwt.verify(vaultToken, JWT_SECRET) as VaultTokenPayload;

      if (decoded.type !== 'vault_access') {
        return res.status(403).json({
          success: false,
          message: 'Invalid vault token type',
        });
      }

      if (decoded.userId !== req.user.id) {
        return res.status(403).json({
          success: false,
          message: 'Invalid vault token',
        });
      }

      next();
    } catch (err) {
      if (err instanceof jwt.TokenExpiredError) {
        return res.status(401).json({
          success: false,
          message: 'Vault token expired. Please re-enter PIN.',
        });
      }
      return res.status(401).json({
        success: false,
        message: 'Invalid vault token',
      });
    }
  } catch (error) {
    next(error);
  }
};
