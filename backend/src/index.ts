import dotenv from 'dotenv';
dotenv.config();

import express, { Application, Request, Response, NextFunction } from 'express';
import { createServer } from 'http';
import cors from 'cors';
import helmet from 'helmet';
import compression from 'compression';
import morgan from 'morgan';
import path from 'path';
import { PrismaClient } from '@prisma/client';
import Redis from 'ioredis';

// Import routes
import authRoutes from './auth/routes/auth.routes';
import userRoutes from './auth/routes/user.routes';
import snapRoutes from './snaps/routes/snap.routes';
import storyRoutes from './stories/routes/story.routes';
import chatRoutes from './chat/routes/chat.routes';
import mediaRoutes from './media/routes/media.routes';
import socialRoutes from './social/routes/social.routes';
import eventRoutes from './events/routes/event.routes';
import discoverRoutes from './discover/routes/discover.routes';
import notificationRoutes from './notifications/routes/notification.routes';
import moderationRoutes from './moderation/routes/moderation.routes';
import adminRoutes from './admin/routes/admin.routes';
import aiRoutes from './ai/routes/ai.routes';
import transportRoutes from './transport/routes/transport.routes';
import memoryRoutes from './memories/routes/memory.routes';
import safetyWalkRoutes from './safety-walk/routes/safety-walk.routes';
import callRoutes from './chat/routes/call.routes';

// Import middleware
import { errorHandler } from './common/middleware/errorHandler';
import { rateLimiter } from './common/middleware/rateLimiter';
import { requestIdMiddleware } from './common/middleware/requestId';
import { authMiddleware } from './auth/middleware/auth.middleware';

// Import jobs
import { initializeJobs } from './common/jobs';

// Initialize Prisma with optimized connection pool
export const prisma = new PrismaClient({
  log: process.env.NODE_ENV === 'development' ? ['error', 'warn'] : ['error'],
  datasources: {
    db: {
      url: `${process.env.DATABASE_URL}&connection_limit=20&pool_timeout=10`,
    },
  },
});

// Initialize Redis (graceful fallback if unavailable)
let redisAvailable = true;
export const redis = new Redis(process.env.REDIS_URL || 'redis://localhost:6379', {
  maxRetriesPerRequest: 1,
  connectTimeout: 3000,
  lazyConnect: true,
  retryStrategy(times) {
    if (times > 3) { redisAvailable = false; return null; }
    return Math.min(times * 200, 1000);
  },
});
redis.on('error', (err) => {
  if (redisAvailable) {
    console.warn('Redis error (non-fatal):', err.message);
    redisAvailable = false;
  }
});
redis.connect().catch(() => { redisAvailable = false; });

// Create Express app and HTTP server
const app: Application = express();
const httpServer = createServer(app);

// CORS origins configuration (shared between Express and Socket.io)
const corsOrigins = process.env.CORS_ORIGINS?.split(',') || ['http://localhost:3000'];

// Middleware
app.use(helmet());
app.use(compression({ level: 6, threshold: 1024 }));  // gzip level 6, skip < 1KB
app.use(cors({
  origin: corsOrigins,
  credentials: true,
}));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(requestIdMiddleware);
if (process.env.NODE_ENV === 'development') app.use(morgan('dev'));

// Cache headers for API responses
app.use((req: Request, res: Response, next: NextFunction) => {
  // No cache for mutations, short cache for reads
  if (req.method === 'GET') {
    res.set('Cache-Control', 'private, max-age=0, stale-while-revalidate=5');
  } else {
    res.set('Cache-Control', 'no-store');
  }
  next();
});

// Rate limiting
app.use(rateLimiter);

// Health check
app.get('/health', (req: Request, res: Response) => {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  });
});

// API routes
const apiVersion = process.env.API_VERSION || 'v1';
const apiPrefix = `/api/${apiVersion}`;

app.use(`${apiPrefix}/auth`, authRoutes);
app.use(`${apiPrefix}/users`, authMiddleware, userRoutes);
app.use(`${apiPrefix}/snaps`, authMiddleware, snapRoutes);
app.use(`${apiPrefix}/stories`, authMiddleware, storyRoutes);
app.use(`${apiPrefix}/chats`, authMiddleware, chatRoutes);
app.use(`${apiPrefix}/media`, authMiddleware, mediaRoutes);
app.use(`${apiPrefix}/social`, authMiddleware, socialRoutes);
app.use(`${apiPrefix}/events`, authMiddleware, eventRoutes);
app.use(`${apiPrefix}/discover`, authMiddleware, discoverRoutes);
app.use(`${apiPrefix}/notifications`, authMiddleware, notificationRoutes);
app.use(`${apiPrefix}/moderation`, authMiddleware, moderationRoutes);
app.use(`${apiPrefix}/memories`, authMiddleware, memoryRoutes);
app.use(`${apiPrefix}/admin`, adminRoutes);
app.use(`${apiPrefix}/ai`, authMiddleware, aiRoutes);
app.use(`${apiPrefix}/transport`, transportRoutes);  // Public - no auth required
app.use(`${apiPrefix}/safety-walk`, authMiddleware, safetyWalkRoutes);
app.use(`${apiPrefix}/calls`, authMiddleware, callRoutes);

// Serve admin panel static files
const adminDistPath = path.join(__dirname, '..', 'admin-dist');
app.use('/admin', express.static(adminDistPath));
app.get('/admin/*', (req: Request, res: Response) => {
  res.sendFile(path.join(adminDistPath, 'index.html'));
});

// 404 handler
app.use((req: Request, res: Response) => {
  res.status(404).json({
    success: false,
    error: 'Not Found',
    message: `Route ${req.method} ${req.path} not found`,
  });
});

// Error handler
app.use(errorHandler);

// Initialize background jobs
initializeJobs();

// Initialize WebSocket server
import { websocketService } from './chat/services/websocket.service';
websocketService.initialize(httpServer, corsOrigins);

// Graceful shutdown
const gracefulShutdown = async () => {
  console.log('Received shutdown signal. Closing connections...');
  
  // Stop stale call cleanup interval
  websocketService.stopStaleCallCleanup();

  await prisma.$disconnect();
  redis.disconnect();
  
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
  
  // Force close after 10 seconds
  setTimeout(() => {
    console.error('Could not close connections in time, forcefully shutting down');
    process.exit(1);
  }, 10000);
};

process.on('SIGTERM', gracefulShutdown);
process.on('SIGINT', gracefulShutdown);

// Start server
const PORT = process.env.PORT || 3000;

const server = httpServer.listen(PORT, () => {
  console.log(`
  🚀 LondonSnaps Backend Server
  ============================
  Environment: ${process.env.NODE_ENV || 'development'}
  Port: ${PORT}
  API Version: ${apiVersion}
  Health: http://localhost:${PORT}/health
  WebSocket: Enabled
  `);
});

export default app;
