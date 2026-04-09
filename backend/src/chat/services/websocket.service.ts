import { Server as HttpServer } from 'http';
import { Server, Socket } from 'socket.io';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import { prisma } from '../../index';
import { logger } from '../../common/utils/logger';
import { authCache, CACHE_TTL } from '../../common/utils/cache';
import { JWTPayload, AuthenticatedUser } from '../../auth/models/auth.types';
import { notificationService } from '../../notifications/services/notification.service';

const JWT_SECRET = process.env.JWT_SECRET!;

// Socket with authenticated user
interface AuthenticatedSocket extends Socket {
  user: AuthenticatedUser;
}

// User connection tracking
const userSockets = new Map<string, Set<string>>(); // userId -> Set<socketId>
const socketUsers = new Map<string, string>(); // socketId -> userId

// Active calls tracking
interface ActiveCall {
  callerId: string;
  targetId: string;
  callType: 'voice' | 'video';
  startTime: Date;
  callerName: string;
  callerAvatar?: string;
}
const activeCalls = new Map<string, ActiveCall>(); // callId -> call info
const callTimeouts = new Map<string, NodeJS.Timeout>(); // callId -> timeout timer

// Rate limiting for typing events
const typingRateLimit = new Map<string, number>(); // key -> last emit timestamp

// Event Types (matching iOS client)
const EVENTS = {
  // Client -> Server
  MESSAGE_SEND: 'send_message',
  MESSAGE_READ: 'mark_read',
  TYPING_START: 'typing',
  TYPING_STOP: 'stop_typing',
  JOIN_CHAT: 'join_chat',
  LEAVE_CHAT: 'leave_chat',
  
  // Server -> Client
  MESSAGE_NEW: 'message',
  MESSAGE_READ_ACK: 'message_read',
  MESSAGE_DELIVERED: 'message:delivered',
  MESSAGE_DELETED: 'message_deleted',
  MESSAGE_EDITED: 'message_edited',
  MESSAGE_REACTION: 'message_reaction',
  MESSAGE_EXPIRED: 'message_expired',
  SNAP_STATUS_UPDATE: 'snap_status_update',
  TYPING: 'typing',
  STOP_TYPING: 'stop_typing',
  USER_ONLINE: 'user_online',
  USER_OFFLINE: 'user_offline',
  ERROR: 'error',
  
  // Call events - Client -> Server
  CALL_INITIATE: 'call_initiate',
  CALL_ACCEPT: 'call_accept',
  CALL_DECLINE: 'call_decline',
  CALL_END: 'call_end',
  CALL_CANCEL: 'call_cancel',
  CALL_OFFER: 'call_offer',
  CALL_ANSWER: 'call_answer',
  CALL_ICE_CANDIDATE: 'call_ice_candidate',
  
  // Call events - Server -> Client
  CALL_INCOMING: 'call_incoming',
  CALL_ACCEPTED: 'call_accepted',
  CALL_DECLINED: 'call_declined',
  CALL_ENDED: 'call_ended',
  CALL_MISSED: 'call_missed',
  CALL_BUSY: 'call_busy',
  CALL_BLOCKED: 'call_blocked',
  CALL_STATE_SYNC: 'call_state_sync',
  CALL_ERROR: 'call_error',
} as const;

// Stale call cleanup interval (cleared on shutdown)
let staleCallCleanupInterval: NodeJS.Timeout | null = null;

class WebSocketService {
  private io: Server | null = null;

  /**
   * Initialize Socket.io with the HTTP server
   */
  initialize(httpServer: HttpServer, corsOrigins: string[]): Server {
    this.io = new Server(httpServer, {
      cors: {
        origin: corsOrigins,
        credentials: true,
      },
      transports: ['websocket', 'polling'],
      pingTimeout: 30000,
      pingInterval: 25000,
    });

    this.io.use(this.authMiddleware.bind(this));
    this.setupEventHandlers();
    this.startStaleCallCleanup();

    // Warn if TURN env vars are missing
    if (!process.env.TURN_USERNAME || !process.env.TURN_CREDENTIAL) {
      logger.warn('[CALL] TURN_USERNAME or TURN_CREDENTIAL not set - calls may fail behind NAT');
    }

    logger.info('WebSocket server initialized');
    return this.io;
  }

  /**
   * JWT Authentication middleware for WebSocket connections
   */
  private async authMiddleware(socket: Socket, next: (err?: Error) => void): Promise<void> {
    try {
      // Extract token from handshake
      const token = socket.handshake.auth.token || 
                    socket.handshake.headers.authorization?.replace('Bearer ', '');

      if (!token) {
        return next(new Error('Authentication required'));
      }

      // Verify JWT
      const decoded = jwt.verify(token, JWT_SECRET) as JWTPayload;

      if (decoded.type !== 'access') {
        return next(new Error('Invalid token type'));
      }

      // Check cache first
      const userCacheKey = `user:${decoded.userId}`;
      const sessionCacheKey = `session:${token}`;
      let user = authCache.get<any>(userCacheKey);
      let session = authCache.get<any>(sessionCacheKey);

      if (!user || !session) {
        const [dbUser, dbSession] = await Promise.all([
          user ? Promise.resolve(user) : prisma.user.findUnique({
            where: { id: decoded.userId },
            select: {
              id: true, email: true, username: true, displayName: true,
              avatarUrl: true, avatarConfig: true, isVerified: true, isUniversityStudent: true,
              universityId: true, status: true,
            },
          }),
          session ? Promise.resolve(session) : prisma.session.findUnique({
            where: { token },
          }),
        ]);
        user = dbUser;
        session = dbSession;
        if (user) authCache.set(userCacheKey, user, CACHE_TTL.AUTH_USER);
        if (session) authCache.set(sessionCacheKey, session, CACHE_TTL.AUTH_SESSION);
      }

      if (!user) {
        return next(new Error('User not found'));
      }

      if (user.status !== 'ACTIVE') {
        return next(new Error('Account is not active'));
      }

      if (!session || session.expiresAt < new Date()) {
        return next(new Error('Session expired'));
      }

      // Attach user to socket
      (socket as AuthenticatedSocket).user = user as AuthenticatedUser;
      next();
    } catch (error) {
      if (error instanceof jwt.JsonWebTokenError) {
        return next(new Error('Invalid token'));
      }
      if (error instanceof jwt.TokenExpiredError) {
        return next(new Error('Token expired'));
      }
      logger.error('WebSocket auth error:', error);
      next(new Error('Authentication failed'));
    }
  }

  /**
   * Setup event handlers for all connections
   */
  private setupEventHandlers(): void {
    if (!this.io) return;

    this.io.on('connection', async (socket: Socket) => {
      const authSocket = socket as AuthenticatedSocket;
      const userId = authSocket.user.id;

      logger.info(`WebSocket connected: ${userId} (${socket.id})`);

      // Track user connection
      this.addUserSocket(userId, socket.id);

      // Join user to all their chat rooms
      await this.joinUserChats(authSocket);

      // Broadcast user online status
      this.broadcastUserStatus(userId, true);

      // Sync active call state on reconnection
      this.syncCallStateOnReconnect(authSocket);

      // Update user online status in DB (fire-and-forget)
      prisma.user.update({
        where: { id: userId },
        data: { isOnline: true, lastSeenAt: new Date() },
      }).catch(() => {});

      // Event handlers
      socket.on(EVENTS.MESSAGE_SEND, (data) => this.handleSendMessage(authSocket, data));
      socket.on(EVENTS.MESSAGE_READ, (data) => this.handleMarkRead(authSocket, data));
      socket.on(EVENTS.TYPING_START, (data) => this.handleTypingStart(authSocket, data));
      socket.on(EVENTS.TYPING_STOP, (data) => this.handleTypingStop(authSocket, data));
      socket.on(EVENTS.JOIN_CHAT, (data) => this.handleJoinChat(authSocket, data));
      socket.on(EVENTS.LEAVE_CHAT, (data) => this.handleLeaveChat(authSocket, data));
      
      // Call event handlers (each wrapped with safe error handling)
      socket.on(EVENTS.CALL_INITIATE, (data) => this.safeCallHandler('call_initiate', authSocket, data, (s, d) => this.handleCallInitiate(s, d)));
      socket.on(EVENTS.CALL_ACCEPT, (data) => this.safeCallHandler('call_accept', authSocket, data, (s, d) => this.handleCallAccept(s, d)));
      socket.on(EVENTS.CALL_DECLINE, (data) => this.safeCallHandler('call_decline', authSocket, data, (s, d) => this.handleCallDecline(s, d)));
      socket.on(EVENTS.CALL_END, (data) => this.safeCallHandler('call_end', authSocket, data, (s, d) => this.handleCallEnd(s, d)));
      socket.on(EVENTS.CALL_CANCEL, (data) => this.safeCallHandler('call_cancel', authSocket, data, (s, d) => this.handleCallCancel(s, d)));
      socket.on(EVENTS.CALL_OFFER, (data) => this.safeCallHandler('call_offer', authSocket, data, (s, d) => this.handleCallOffer(s, d)));
      socket.on(EVENTS.CALL_ANSWER, (data) => this.safeCallHandler('call_answer', authSocket, data, (s, d) => this.handleCallAnswer(s, d)));
      socket.on(EVENTS.CALL_ICE_CANDIDATE, (data) => this.safeCallHandler('call_ice_candidate', authSocket, data, (s, d) => this.handleCallIceCandidate(s, d)));

      // Disconnect handler
      socket.on('disconnect', () => this.handleDisconnect(authSocket));
    });
  }

  /**
   * Handle user disconnect
   */
  private handleDisconnect(socket: AuthenticatedSocket): void {
    const userId = socket.user.id;
    this.removeUserSocket(userId, socket.id);

    logger.info(`WebSocket disconnected: ${userId} (${socket.id})`);

    // Clean up any active calls for this user
    this.cleanupUserCalls(userId);

    // Only broadcast offline if user has no more connections
    if (!this.isUserOnline(userId)) {
      this.broadcastUserStatus(userId, false);

      // Update user offline status in DB (fire-and-forget)
      prisma.user.update({
        where: { id: userId },
        data: { isOnline: false, lastSeenAt: new Date() },
      }).catch(() => {});
    }
  }

  /**
   * Clean up active calls when a user disconnects
   */
  private cleanupUserCalls(userId: string): void {
    for (const [callId, call] of Array.from(activeCalls.entries())) {
      if (call.callerId === userId || call.targetId === userId) {
        const otherUserId = call.callerId === userId ? call.targetId : call.callerId;
        const duration = Math.floor((Date.now() - call.startTime.getTime()) / 1000);
        
        // Emit call ended to the other party
        this.emitToUser(otherUserId, EVENTS.CALL_ENDED, { callId, duration });
        
        // Clear timeout and remove call
        const timeout = callTimeouts.get(callId);
        if (timeout) {
          clearTimeout(timeout);
          callTimeouts.delete(callId);
        }
        activeCalls.delete(callId);

        // Log failed/interrupted call
        prisma.callLog.create({
          data: {
            callerId: call.callerId,
            receiverId: call.targetId,
            callType: call.callType === 'voice' ? 'VOICE' : 'VIDEO',
            status: duration > 0 ? 'COMPLETED' : 'FAILED',
            duration,
            startedAt: call.startTime,
            endedAt: new Date(),
          },
        }).catch((err: any) => logger.error('[CALL] Failed to log interrupted call:', err));
        
        logger.info(`[CALL] Call ended: callId=${callId}, duration=${duration}s (user ${userId} disconnected)`);
      }
    }
  }

  /**
   * Top-level error wrapper for all call socket event handlers.
   * Catches unhandled errors, logs them, emits call_error, and attempts graceful cleanup.
   */
  private async safeCallHandler(
    eventName: string,
    socket: AuthenticatedSocket,
    data: any,
    handler: (socket: AuthenticatedSocket, data: any) => void | Promise<void>,
  ): Promise<void> {
    try {
      await handler(socket, data);
    } catch (error) {
      const callId = data?.callId as string | undefined;
      logger.error(`[CALL] Error in ${eventName} handler:`, error);
      socket.emit(EVENTS.CALL_ERROR, { callId: callId ?? null, error: 'Internal server error' });

      // If this was during an active call, try to gracefully end it
      if (callId) {
        const call = activeCalls.get(callId);
        if (call) {
          const otherUserId = call.callerId === socket.user.id ? call.targetId : call.callerId;
          const duration = Math.floor((Date.now() - call.startTime.getTime()) / 1000);
          this.emitToUser(otherUserId, EVENTS.CALL_ENDED, { callId, duration });
          const timeout = callTimeouts.get(callId);
          if (timeout) { clearTimeout(timeout); callTimeouts.delete(callId); }
          activeCalls.delete(callId);
          prisma.callLog.create({
            data: {
              callerId: call.callerId,
              receiverId: call.targetId,
              callType: call.callType === 'voice' ? 'VOICE' : 'VIDEO',
              status: 'FAILED',
              duration,
              startedAt: call.startTime,
              endedAt: new Date(),
            },
          }).catch((err: any) => logger.error('[CALL] Failed to log error-cleanup call:', err));
          logger.warn(`[CALL] Gracefully ended call ${callId} after error in ${eventName}`);
        }
      }
    }
  }

  /**
   * Start periodic cleanup of stale calls (>5 minutes active).
   * Runs every 60 seconds.
   */
  private startStaleCallCleanup(): void {
    staleCallCleanupInterval = setInterval(() => {
      const now = Date.now();
      for (const [callId, call] of Array.from(activeCalls.entries())) {
        const seconds = Math.floor((now - call.startTime.getTime()) / 1000);
        if (seconds > 300) {
          logger.warn(`[CALL] Cleaning stale call ${callId}, duration: ${seconds}s`);

          // Notify both parties
          this.emitToUser(call.callerId, EVENTS.CALL_ENDED, { callId, reason: 'timeout' });
          this.emitToUser(call.targetId, EVENTS.CALL_ENDED, { callId, reason: 'timeout' });

          // Clear timeout
          const timeout = callTimeouts.get(callId);
          if (timeout) { clearTimeout(timeout); callTimeouts.delete(callId); }

          // Log to DB as FAILED
          prisma.callLog.create({
            data: {
              callerId: call.callerId,
              receiverId: call.targetId,
              callType: call.callType === 'voice' ? 'VOICE' : 'VIDEO',
              status: 'FAILED',
              duration: seconds,
              startedAt: call.startTime,
              endedAt: new Date(),
            },
          }).catch((err: any) => logger.error('[CALL] Failed to log stale call:', err));

          activeCalls.delete(callId);
        }
      }
    }, 60_000);
  }

  /**
   * Stop the stale call cleanup interval (called on shutdown).
   */
  stopStaleCallCleanup(): void {
    if (staleCallCleanupInterval) {
      clearInterval(staleCallCleanupInterval);
      staleCallCleanupInterval = null;
      logger.info('[CALL] Stale call cleanup interval cleared');
    }
  }

  /**
   * Join user to all their chat rooms on connection
   */
  private async joinUserChats(socket: AuthenticatedSocket): Promise<void> {
    try {
      const memberships = await prisma.chatMember.findMany({
        where: { userId: socket.user.id, leftAt: null },
        select: { chatId: true },
      });

      for (const membership of memberships) {
        socket.join(`chat:${membership.chatId}`);
      }

      logger.debug(`User ${socket.user.id} joined ${memberships.length} chat rooms`);
    } catch (error) {
      logger.error('Error joining user chats:', error);
    }
  }

  /**
   * Handle send message event
   */
  private async handleSendMessage(
    socket: AuthenticatedSocket,
    data: { chatId: string; content?: string; type?: string; mediaUrl?: string; replyToId?: string }
  ): Promise<void> {
    try {
      const { chatId, content, type = 'TEXT', mediaUrl, replyToId } = data;

      if (!chatId) {
        socket.emit(EVENTS.ERROR, { message: 'chatId is required' });
        return;
      }

      // Verify membership
      const member = await prisma.chatMember.findUnique({
        where: { chatId_userId: { chatId, userId: socket.user.id } },
      });

      if (!member || member.leftAt) {
        socket.emit(EVENTS.ERROR, { message: 'Not a member of this chat' });
        return;
      }

      // Create message
      const message = await prisma.message.create({
        data: {
          chatId,
          senderId: socket.user.id,
          type: type as any,
          content,
          mediaUrl,
          replyToId,
        },
        include: {
          sender: {
            select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true },
          },
          replyTo: {
            select: {
              id: true, content: true, type: true,
              sender: { select: { id: true, displayName: true } },
            },
          },
        },
      });

      // Update chat lastMessageAt
      prisma.chat.update({
        where: { id: chatId },
        data: { lastMessageAt: new Date() },
      }).catch(() => {});

      // Broadcast to all chat members
      this.emitToChat(chatId, EVENTS.MESSAGE_NEW, message);

      logger.debug(`Message sent in chat ${chatId} by ${socket.user.id}`);
    } catch (error) {
      logger.error('Error sending message via WebSocket:', error);
      socket.emit(EVENTS.ERROR, { message: 'Failed to send message' });
    }
  }

  /**
   * Handle mark read event
   */
  private async handleMarkRead(
    socket: AuthenticatedSocket,
    data: { chatId: string; messageIds?: string[] }
  ): Promise<void> {
    try {
      const { chatId, messageIds } = data;

      if (!chatId) {
        socket.emit(EVENTS.ERROR, { message: 'chatId is required' });
        return;
      }

      // Update lastReadAt
      await prisma.chatMember.update({
        where: { chatId_userId: { chatId, userId: socket.user.id } },
        data: { lastReadAt: new Date() },
      });

      // Create read receipts for specific messages
      if (messageIds && messageIds.length > 0) {
        await Promise.all(
          messageIds.map((messageId) =>
            prisma.messageReadReceipt.upsert({
              where: { messageId_userId: { messageId, userId: socket.user.id } },
              update: { readAt: new Date() },
              create: { messageId, userId: socket.user.id },
            })
          )
        );

        // Notify message senders about read receipts
        for (const messageId of messageIds) {
          const message = await prisma.message.findUnique({
            where: { id: messageId },
            select: { senderId: true },
          });

          if (message && message.senderId !== socket.user.id) {
            this.emitToUser(message.senderId, EVENTS.MESSAGE_READ_ACK, {
              messageId,
              chatId,
              userId: socket.user.id,
              readAt: new Date().toISOString(),
            });
          }
        }
      }

      logger.debug(`Messages marked read in chat ${chatId} by ${socket.user.id}`);
    } catch (error) {
      logger.error('Error marking messages read:', error);
      socket.emit(EVENTS.ERROR, { message: 'Failed to mark as read' });
    }
  }

  /**
   * Handle typing start event (with rate limiting)
   */
  private handleTypingStart(socket: AuthenticatedSocket, data: { chatId: string }): void {
    const { chatId } = data;
    if (!chatId) return;

    // Rate limit: max 1 typing event per second per user per chat
    const key = `${socket.user.id}:${chatId}`;
    const now = Date.now();
    const lastEmit = typingRateLimit.get(key) || 0;
    if (now - lastEmit < 1000) return; // Throttle to 1 per second
    typingRateLimit.set(key, now);

    socket.to(`chat:${chatId}`).emit(EVENTS.TYPING, {
      id: `${socket.user.id}-${chatId}`,
      chatId,
      userId: socket.user.id,
      user: {
        id: socket.user.id,
        username: socket.user.username,
        displayName: socket.user.displayName,
        avatarUrl: socket.user.avatarUrl,
        isOnline: true,
      },
    });
  }

  /**
   * Handle typing stop event
   */
  private handleTypingStop(socket: AuthenticatedSocket, data: { chatId: string }): void {
    const { chatId } = data;
    if (!chatId) return;

    socket.to(`chat:${chatId}`).emit(EVENTS.STOP_TYPING, {
      chatId,
      userId: socket.user.id,
    });
  }

  /**
   * Handle join chat event (for dynamic chat joins)
   */
  private handleJoinChat(socket: AuthenticatedSocket, data: { chatId: string }): void {
    const { chatId } = data;
    if (!chatId) return;

    socket.join(`chat:${chatId}`);
    logger.debug(`User ${socket.user.id} joined chat room ${chatId}`);
  }

  /**
   * Handle leave chat event
   */
  private handleLeaveChat(socket: AuthenticatedSocket, data: { chatId: string }): void {
    const { chatId } = data;
    if (!chatId) return;

    socket.leave(`chat:${chatId}`);
    logger.debug(`User ${socket.user.id} left chat room ${chatId}`);
  }

  // ============================================
  // Call signaling handlers
  // ============================================

  /**
   * Handle call initiation
   */
  private async handleCallInitiate(
    socket: AuthenticatedSocket,
    data: { targetUserId: string; callType: 'voice' | 'video' }
  ): Promise<void> {
    try {
      const { targetUserId, callType } = data;
      const callerId = socket.user.id;

      if (!targetUserId || !callType) {
        socket.emit(EVENTS.ERROR, { message: 'targetUserId and callType are required' });
        return;
      }

      if (targetUserId === callerId) {
        socket.emit(EVENTS.ERROR, { message: 'Cannot call yourself' });
        return;
      }

      // Block check: deny if either party has blocked the other
      const blockExists = await prisma.block.findFirst({
        where: {
          OR: [
            { blockerId: callerId, blockedId: targetUserId },
            { blockerId: targetUserId, blockedId: callerId },
          ],
        },
      });

      if (blockExists) {
        // Generate callId so client can match the response
        const callId = uuidv4();
        socket.emit(EVENTS.CALL_BLOCKED, { callId });
        logger.info(`Call blocked between ${callerId} and ${targetUserId}`);
        return;
      }

      // Busy check: deny if CALLER is already in an active call
      const callerInCall = Array.from(activeCalls.values()).some(
        (c) => c.callerId === callerId || c.targetId === callerId
      );

      if (callerInCall) {
        const callId = uuidv4();
        socket.emit(EVENTS.CALL_BUSY, { callId });
        logger.info(`[CALL] Call from ${callerId} rejected: caller already in active call`);
        return;
      }

      // Busy check: deny if target is already in an active call
      const targetInCall = Array.from(activeCalls.values()).some(
        (c) => c.callerId === targetUserId || c.targetId === targetUserId
      );

      if (targetInCall) {
        const callId = uuidv4();
        socket.emit('call_initiated', { callId });
        // Immediately tell caller the target is busy
        socket.emit(EVENTS.CALL_BUSY, { callId });
        logger.info(`[CALL] Call to ${targetUserId} rejected: user is busy`);
        return;
      }

      // Generate unique call ID
      const callId = uuidv4();

      // Store call in active calls
      const call: ActiveCall = {
        callerId,
        targetId: targetUserId,
        callType,
        startTime: new Date(),
        callerName: socket.user.displayName,
        callerAvatar: socket.user.avatarUrl ?? undefined,
      };
      activeCalls.set(callId, call);

      logger.info(`[CALL] Call initiated: callId=${callId}, caller=${callerId}, target=${targetUserId}, type=${callType}`);

      // Check if target user is online
      const isTargetOnline = this.isUserOnline(targetUserId);

      if (isTargetOnline) {
        // Emit incoming call to target's socket(s)
        this.emitToUser(targetUserId, EVENTS.CALL_INCOMING, {
          callId,
          callerId,
          callerName: socket.user.displayName,
          callerAvatar: socket.user.avatarUrl,
          callType,
        });
      } else {
        // Send push notification for incoming call
        const callTypeLabel = callType === 'voice' ? 'voice' : 'video';
        notificationService.sendPushNotification(targetUserId, {
          type: 'INCOMING_CALL',
          title: 'Incoming Call',
          body: `Incoming ${callTypeLabel} call from ${socket.user.displayName}`,
          data: {
            callId,
            callerId,
            callType,
          },
        }).catch((err) => logger.error('Failed to send call push notification:', err));
      }

      // Set 30-second timeout for unanswered calls
      const timeout = setTimeout(() => {
        const activeCall = activeCalls.get(callId);
        if (activeCall) {
          // Call was not answered - emit missed to both parties
          this.emitToUser(callerId, EVENTS.CALL_MISSED, { callId });
          this.emitToUser(targetUserId, EVENTS.CALL_MISSED, { callId });
          
          activeCalls.delete(callId);
          callTimeouts.delete(callId);
          
          // Log missed call
          prisma.callLog.create({
            data: {
              callerId,
              receiverId: targetUserId,
              callType: callType === 'voice' ? 'VOICE' : 'VIDEO',
              status: 'MISSED',
              duration: 0,
              endedAt: new Date(),
            },
          }).catch((err: any) => logger.error('Failed to log missed call:', err));
          
          logger.info(`[CALL] Call missed: callId=${callId}`);
        }
      }, 30000);

      callTimeouts.set(callId, timeout);

      // Acknowledge call initiation to caller
      socket.emit('call_initiated', { callId });
    } catch (error) {
      logger.error('[CALL] Error in call_initiate handler:', error);
      socket.emit(EVENTS.CALL_ERROR, { callId: null, error: 'Internal server error' });
    }
  }

  /**
   * Handle call accept
   */
  private handleCallAccept(
    socket: AuthenticatedSocket,
    data: { callId: string }
  ): void {
    try {
      const { callId } = data;
      const userId = socket.user.id;

      if (!callId) {
        socket.emit(EVENTS.ERROR, { message: 'callId is required' });
        return;
      }

      const call = activeCalls.get(callId);
      if (!call) {
        socket.emit(EVENTS.CALL_ERROR, { callId, error: 'Call not found or expired' });
        return;
      }

      // Verify user is the target of the call
      if (call.targetId !== userId) {
        socket.emit(EVENTS.CALL_ERROR, { callId, error: 'Not authorized to accept this call' });
        return;
      }

      // Clear the timeout timer
      const timeout = callTimeouts.get(callId);
      if (timeout) {
        clearTimeout(timeout);
        callTimeouts.delete(callId);
      }

      // Emit call accepted to caller
      this.emitToUser(call.callerId, EVENTS.CALL_ACCEPTED, { callId });

      logger.info(`[CALL] Call accepted: callId=${callId}`);
    } catch (error) {
      logger.error(`[CALL] Error in call_accept handler:`, error);
      socket.emit(EVENTS.CALL_ERROR, { callId: data?.callId ?? null, error: 'Internal server error' });
    }
  }

  /**
   * Handle call decline
   */
  private handleCallDecline(
    socket: AuthenticatedSocket,
    data: { callId: string }
  ): void {
    try {
      const { callId } = data;
      const userId = socket.user.id;

      if (!callId) {
        socket.emit(EVENTS.ERROR, { message: 'callId is required' });
        return;
      }

      const call = activeCalls.get(callId);
      if (!call) {
        socket.emit(EVENTS.CALL_ERROR, { callId, error: 'Call not found or expired' });
        return;
      }

      // Verify user is the target of the call
      if (call.targetId !== userId) {
        socket.emit(EVENTS.CALL_ERROR, { callId, error: 'Not authorized to decline this call' });
        return;
      }

      // Clear the timeout timer
      const timeout = callTimeouts.get(callId);
      if (timeout) {
        clearTimeout(timeout);
        callTimeouts.delete(callId);
      }

      // Emit call declined to caller
      this.emitToUser(call.callerId, EVENTS.CALL_DECLINED, { callId });

      // Remove call from active calls
      activeCalls.delete(callId);

      // Log declined call
      prisma.callLog.create({
        data: {
          callerId: call.callerId,
          receiverId: call.targetId,
          callType: call.callType === 'voice' ? 'VOICE' : 'VIDEO',
          status: 'DECLINED',
          duration: 0,
          endedAt: new Date(),
        },
      }).catch((err: any) => logger.error('Failed to log declined call:', err));

      logger.info(`[CALL] Call declined: callId=${callId}`);
    } catch (error) {
      logger.error(`[CALL] Error in call_decline handler:`, error);
      socket.emit(EVENTS.CALL_ERROR, { callId: data?.callId ?? null, error: 'Internal server error' });
    }
  }

  /**
   * Handle call cancel (caller cancels during ringing phase)
   */
  private handleCallCancel(
    socket: AuthenticatedSocket,
    data: { callId: string }
  ): void {
    try {
      const { callId } = data;
      const userId = socket.user.id;

      if (!callId) {
        socket.emit(EVENTS.ERROR, { message: 'callId is required' });
        return;
      }

      const call = activeCalls.get(callId);
      if (!call) {
        socket.emit(EVENTS.CALL_ERROR, { callId, error: 'Call not found or expired' });
        return;
      }

      // Verify user is the caller (only caller can cancel)
      if (call.callerId !== userId) {
        socket.emit(EVENTS.CALL_ERROR, { callId, error: 'Not authorized to cancel this call' });
        return;
      }

      // Clear the timeout timer
      const timeout = callTimeouts.get(callId);
      if (timeout) {
        clearTimeout(timeout);
        callTimeouts.delete(callId);
      }

      // Emit call ended to the target (so their ringing stops)
      this.emitToUser(call.targetId, EVENTS.CALL_ENDED, { callId, duration: 0 });

      // Remove call from active calls
      activeCalls.delete(callId);

      // Log cancelled call
      prisma.callLog.create({
        data: {
          callerId: call.callerId,
          receiverId: call.targetId,
          callType: call.callType === 'voice' ? 'VOICE' : 'VIDEO',
          status: 'MISSED',
          duration: 0,
          endedAt: new Date(),
        },
      }).catch((err: any) => logger.error('Failed to log cancelled call:', err));

      logger.info(`[CALL] Call cancelled: callId=${callId}, by=${userId}`);
    } catch (error) {
      logger.error(`[CALL] Error in call_cancel handler:`, error);
      socket.emit(EVENTS.CALL_ERROR, { callId: data?.callId ?? null, error: 'Internal server error' });
    }
  }

  /**
   * Handle call end
   */
  private handleCallEnd(
    socket: AuthenticatedSocket,
    data: { callId: string }
  ): void {
    try {
      const { callId } = data;
      const userId = socket.user.id;

      if (!callId) {
        socket.emit(EVENTS.ERROR, { message: 'callId is required' });
        return;
      }

      const call = activeCalls.get(callId);
      if (!call) {
        socket.emit(EVENTS.CALL_ERROR, { callId, error: 'Call not found or expired' });
        return;
      }

      // Verify user is part of the call
      if (call.callerId !== userId && call.targetId !== userId) {
        socket.emit(EVENTS.CALL_ERROR, { callId, error: 'Not authorized to end this call' });
        return;
      }

      // Calculate call duration
      const duration = Math.floor((Date.now() - call.startTime.getTime()) / 1000);

      // Clear the timeout timer if exists
      const timeout = callTimeouts.get(callId);
      if (timeout) {
        clearTimeout(timeout);
        callTimeouts.delete(callId);
      }

      // Determine the other party
      const otherUserId = call.callerId === userId ? call.targetId : call.callerId;

      // Emit call ended to the other party
      this.emitToUser(otherUserId, EVENTS.CALL_ENDED, { callId, duration });

      // Remove call from active calls
      activeCalls.delete(callId);

      // Log completed call
      prisma.callLog.create({
        data: {
          callerId: call.callerId,
          receiverId: call.targetId,
          callType: call.callType === 'voice' ? 'VOICE' : 'VIDEO',
          status: 'COMPLETED',
          duration,
          startedAt: call.startTime,
          endedAt: new Date(),
        },
      }).catch((err: any) => logger.error('Failed to log completed call:', err));

      logger.info(`[CALL] Call ended: callId=${callId}, duration=${duration}s`);
    } catch (error) {
      logger.error(`[CALL] Error in call_end handler:`, error);
      socket.emit(EVENTS.CALL_ERROR, { callId: data?.callId ?? null, error: 'Internal server error' });
    }
  }

  /**
   * Handle WebRTC SDP offer relay
   */
  private handleCallOffer(
    socket: AuthenticatedSocket,
    data: { callId: string; sdp: any }
  ): void {
    try {
      const { callId, sdp } = data;
      const userId = socket.user.id;

      if (!callId || !sdp) {
        socket.emit(EVENTS.ERROR, { message: 'callId and sdp are required' });
        return;
      }

      const call = activeCalls.get(callId);
      if (!call) {
        socket.emit(EVENTS.CALL_ERROR, { callId, error: 'Call not found or expired' });
        return;
      }

      // Verify user is part of the call
      if (call.callerId !== userId && call.targetId !== userId) {
        socket.emit(EVENTS.CALL_ERROR, { callId, error: 'Not authorized for this call' });
        return;
      }

      // Relay offer to the other party
      const otherUserId = call.callerId === userId ? call.targetId : call.callerId;
      this.emitToUser(otherUserId, EVENTS.CALL_OFFER, { callId, sdp });

      logger.info(`[CALL] SDP offer relayed: callId=${callId}`);
    } catch (error) {
      logger.error(`[CALL] Error in call_offer handler:`, error);
      socket.emit(EVENTS.CALL_ERROR, { callId: data?.callId ?? null, error: 'Internal server error' });
    }
  }

  /**
   * Handle WebRTC SDP answer relay
   */
  private handleCallAnswer(
    socket: AuthenticatedSocket,
    data: { callId: string; sdp: any }
  ): void {
    try {
      const { callId, sdp } = data;
      const userId = socket.user.id;

      if (!callId || !sdp) {
        socket.emit(EVENTS.ERROR, { message: 'callId and sdp are required' });
        return;
      }

      const call = activeCalls.get(callId);
      if (!call) {
        socket.emit(EVENTS.CALL_ERROR, { callId, error: 'Call not found or expired' });
        return;
      }

      // Verify user is part of the call
      if (call.callerId !== userId && call.targetId !== userId) {
        socket.emit(EVENTS.CALL_ERROR, { callId, error: 'Not authorized for this call' });
        return;
      }

      // Relay answer to the caller
      this.emitToUser(call.callerId, EVENTS.CALL_ANSWER, { callId, sdp });

      logger.info(`[CALL] SDP answer relayed: callId=${callId}`);
    } catch (error) {
      logger.error(`[CALL] Error in call_answer handler:`, error);
      socket.emit(EVENTS.CALL_ERROR, { callId: data?.callId ?? null, error: 'Internal server error' });
    }
  }

  /**
   * Handle WebRTC ICE candidate relay
   */
  private handleCallIceCandidate(
    socket: AuthenticatedSocket,
    data: { callId: string; candidate: any }
  ): void {
    try {
      const { callId, candidate } = data;
      const userId = socket.user.id;

      if (!callId || !candidate) {
        socket.emit(EVENTS.ERROR, { message: 'callId and candidate are required' });
        return;
      }

      const call = activeCalls.get(callId);
      if (!call) {
        socket.emit(EVENTS.CALL_ERROR, { callId, error: 'Call not found or expired' });
        return;
      }

      // Verify user is part of the call
      if (call.callerId !== userId && call.targetId !== userId) {
        socket.emit(EVENTS.CALL_ERROR, { callId, error: 'Not authorized for this call' });
        return;
      }

      // Relay ICE candidate to the other party
      const otherUserId = call.callerId === userId ? call.targetId : call.callerId;
      this.emitToUser(otherUserId, EVENTS.CALL_ICE_CANDIDATE, { callId, candidate });

      logger.info(`[CALL] ICE candidate relayed: callId=${callId}`);
    } catch (error) {
      logger.error(`[CALL] Error in call_ice_candidate handler:`, error);
      socket.emit(EVENTS.CALL_ERROR, { callId: data?.callId ?? null, error: 'Internal server error' });
    }
  }

  /**
   * Sync active call state when a user reconnects.
   * If the user is part of an active call, inform them so the client can recover.
   */
  private syncCallStateOnReconnect(socket: AuthenticatedSocket): void {
    const userId = socket.user.id;

    for (const [callId, call] of Array.from(activeCalls.entries())) {
      if (call.callerId === userId || call.targetId === userId) {
        const otherUserId = call.callerId === userId ? call.targetId : call.callerId;
        const isInitiator = call.callerId === userId;

        socket.emit(EVENTS.CALL_STATE_SYNC, {
          callId,
          callType: call.callType,
          otherUserId,
          isInitiator,
          startTime: call.startTime.toISOString(),
        });

        logger.info(`Synced active call ${callId} state to reconnected user ${userId}`);
        break; // A user can only be in one call
      }
    }
  }

  // ============================================
  // Public methods for HTTP → WebSocket bridge
  // ============================================

  /**
   * Emit a new message to all chat members (called from HTTP endpoint)
   * Emits to the chat room, and only to individual members who are NOT already in the room.
   */
  emitNewMessage(chatId: string, message: any): void {
    // Emit to chat room (for users who have the chat open)
    this.emitToChat(chatId, EVENTS.MESSAGE_NEW, message);

    // Get room sockets to check who's already receiving via room
    const roomSockets = this.io?.sockets.adapter.rooms.get(`chat:${chatId}`);

    // Also emit directly to chat members NOT in the room
    // This is crucial for newly created chats (e.g., from snap messages)
    prisma.chatMember.findMany({
      where: { chatId, leftAt: null },
      select: { userId: true },
    }).then((members) => {
      for (const member of members) {
        const memberSocketIds = userSockets.get(member.userId);
        if (!memberSocketIds || memberSocketIds.size === 0) continue;

        // Check if ANY of user's sockets are in the room
        const isInRoom = [...memberSocketIds].some(sid => roomSockets?.has(sid));
        if (!isInRoom) {
          // User not in room, emit individually
          this.emitToUser(member.userId, EVENTS.MESSAGE_NEW, message);
        }
      }
    }).catch((error) => {
      logger.error('Error emitting new message to chat members:', error);
    });
  }

  /**
   * Emit message read receipt (called from HTTP endpoint)
   */
  emitMessageRead(senderId: string, data: { messageId: string; chatId: string; userId: string }): void {
    this.emitToUser(senderId, EVENTS.MESSAGE_READ_ACK, {
      ...data,
      readAt: new Date().toISOString(),
    });
  }

  /**
   * Emit message deleted (called from HTTP endpoint)
   */
  emitMessageDeleted(chatId: string, messageId: string): void {
    this.emitToChat(chatId, EVENTS.MESSAGE_DELETED, { messageId, chatId });
  }

  /**
   * Emit message edited (called from HTTP endpoint)
   */
  emitMessageEdited(chatId: string, message: { id: string; content: string | null; isEdited: boolean; updatedAt: Date }): void {
    this.emitToChat(chatId, EVENTS.MESSAGE_EDITED, { chatId, message });
  }

  /**
   * Emit message reaction (called from HTTP endpoint)
   */
  emitMessageReaction(chatId: string, data: { messageId: string; userId: string; emoji: string; action: 'add' | 'remove' }): void {
    this.emitToChat(chatId, EVENTS.MESSAGE_REACTION, { chatId, ...data });
  }

  /**
   * Emit messages expired (called from cron job for disappearing messages)
   */
  emitMessagesExpired(chatId: string, messageIds: string[]): void {
    this.emitToChat(chatId, EVENTS.MESSAGE_EXPIRED, { chatId, messageIds });
  }

  /**
   * Emit background changed (called from controller)
   */
  emitBackgroundChanged(chatId: string, backgroundUrl: string | null): void {
    this.emitToChat(chatId, 'background_changed', { chatId, backgroundUrl });
  }

  /**
   * Emit message delivered notification (called from HTTP endpoint)
   * Notifies the sender(s) that their messages have been delivered to a recipient
   */
  emitMessageDelivered(chatId: string, messageIds: string[], deliveredByUserId: string): void {
    const deliveredAt = new Date().toISOString();

    // Get message senders to notify them
    prisma.message.findMany({
      where: {
        id: { in: messageIds },
        chatId,
      },
      select: { id: true, senderId: true },
    }).then((messages) => {
      // Group messages by sender
      const senderMessageMap = new Map<string, string[]>();
      for (const msg of messages) {
        if (!senderMessageMap.has(msg.senderId)) {
          senderMessageMap.set(msg.senderId, []);
        }
        senderMessageMap.get(msg.senderId)!.push(msg.id);
      }

      // Emit to each sender
      for (const [senderId, msgIds] of senderMessageMap) {
        this.emitToUser(senderId, EVENTS.MESSAGE_DELIVERED, {
          chatId,
          messageIds: msgIds,
          deliveredBy: deliveredByUserId,
          deliveredAt,
        });
      }
    }).catch((error) => {
      logger.error('Error emitting message delivered:', error);
    });
  }

  /**
   * Emit snap status update (called when snap is viewed/opened/replayed/screenshot)
   * Emits to the chat room, and only to individual members who are NOT already in the room.
   */
  emitSnapStatusUpdate(
    chatId: string,
    data: { chatId: string; messageId: string; snapId: string; status: string; updatedAt: Date }
  ): void {
    // Emit to chat room
    this.emitToChat(chatId, EVENTS.SNAP_STATUS_UPDATE, data);

    // Get room sockets to check who's already receiving via room
    const roomSockets = this.io?.sockets.adapter.rooms.get(`chat:${chatId}`);

    // Also emit directly to chat members NOT in the room
    prisma.chatMember.findMany({
      where: { chatId, leftAt: null },
      select: { userId: true },
    }).then((members) => {
      for (const member of members) {
        const memberSocketIds = userSockets.get(member.userId);
        if (!memberSocketIds || memberSocketIds.size === 0) continue;

        // Check if ANY of user's sockets are in the room
        const isInRoom = [...memberSocketIds].some(sid => roomSockets?.has(sid));
        if (!isInRoom) {
          // User not in room, emit individually
          this.emitToUser(member.userId, EVENTS.SNAP_STATUS_UPDATE, data);
        }
      }
    }).catch((error) => {
      logger.error('Error emitting snap status update to chat members:', error);
    });
  }

  /**
   * Check if a user is currently online
   */
  isUserOnline(userId: string): boolean {
    const sockets = userSockets.get(userId);
    return sockets ? sockets.size > 0 : false;
  }

  /**
   * Get all online user IDs
   */
  getOnlineUserIds(): string[] {
    return Array.from(userSockets.keys());
  }

  // ============================================
  // Helper methods
  // ============================================

  private addUserSocket(userId: string, socketId: string): void {
    if (!userSockets.has(userId)) {
      userSockets.set(userId, new Set());
    }
    userSockets.get(userId)!.add(socketId);
    socketUsers.set(socketId, userId);
  }

  private removeUserSocket(userId: string, socketId: string): void {
    const sockets = userSockets.get(userId);
    if (sockets) {
      sockets.delete(socketId);
      if (sockets.size === 0) {
        userSockets.delete(userId);
      }
    }
    socketUsers.delete(socketId);
  }

  private emitToChat(chatId: string, event: string, data: any): void {
    if (this.io) {
      this.io.to(`chat:${chatId}`).emit(event, data);
    }
  }

  private emitToUser(userId: string, event: string, data: any): void {
    const sockets = userSockets.get(userId);
    if (sockets && this.io) {
      for (const socketId of sockets) {
        this.io.to(socketId).emit(event, data);
      }
    }
  }

  private broadcastUserStatus(userId: string, isOnline: boolean): void {
    if (!this.io) return;

    // Get user's friends to notify them
    prisma.friendship.findMany({
      where: { userId },
      select: { friendId: true },
    }).then((friendships) => {
      for (const { friendId } of friendships) {
        this.emitToUser(friendId, isOnline ? EVENTS.USER_ONLINE : EVENTS.USER_OFFLINE, {
          userId,
        });
      }
    }).catch(() => {});
  }

  /**
   * Get the Socket.io server instance
   */
  getIO(): Server | null {
    return this.io;
  }
}

export const websocketService = new WebSocketService();
