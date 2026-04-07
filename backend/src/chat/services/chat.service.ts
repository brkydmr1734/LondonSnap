import { prisma } from '../../index';
import { websocketService } from './websocket.service';

export type SnapMessageStatus = 'SENT' | 'DELIVERED' | 'OPENED' | 'REPLAYED' | 'SCREENSHOT';

interface SnapMessageContent {
  snapId: string;
  mediaType: 'IMAGE' | 'VIDEO';
  status: SnapMessageStatus;
}

export class ChatService {
  /**
   * Find or create a direct chat between two users
   */
  async getOrCreateDirectChat(userId1: string, userId2: string): Promise<string> {
    // Find existing direct chat
    const existingChat = await prisma.chat.findFirst({
      where: {
        type: 'DIRECT',
        AND: [
          { members: { some: { userId: userId1 } } },
          { members: { some: { userId: userId2 } } },
        ],
      },
      select: { id: true },
    });

    if (existingChat) {
      return existingChat.id;
    }

    // Create new direct chat
    const chat = await prisma.chat.create({
      data: {
        type: 'DIRECT',
        members: {
          createMany: {
            data: [{ userId: userId1 }, { userId: userId2 }],
          },
        },
      },
    });

    return chat.id;
  }

  /**
   * Create a SNAP message in a chat
   */
  async createSnapMessage(
    chatId: string,
    senderId: string,
    snapId: string,
    mediaType: 'IMAGE' | 'VIDEO'
  ): Promise<any> {
    const content: SnapMessageContent = {
      snapId,
      mediaType,
      status: 'SENT',
    };

    const message = await prisma.message.create({
      data: {
        chatId,
        senderId,
        type: 'SNAP',
        content: JSON.stringify(content),
      },
      include: {
        sender: {
          select: {
            id: true,
            username: true,
            displayName: true,
            avatarUrl: true,
            avatarConfig: true,
          },
        },
      },
    });

    // Update chat lastMessageAt - await to ensure it completes before WebSocket emission
    await prisma.chat.update({
      where: { id: chatId },
      data: { lastMessageAt: new Date() },
    }).catch(() => {});

    // Emit new message via WebSocket
    websocketService.emitNewMessage(chatId, message);

    return message;
  }

  /**
   * Update the status of a SNAP message
   * Finds the message by snapId in its content JSON
   */
  async updateSnapMessageStatus(
    snapId: string,
    newStatus: SnapMessageStatus
  ): Promise<{ chatId: string; messageId: string; updatedAt: Date } | null> {
    try {
      // Use a more targeted query with orderBy to get the most recent matching message first
      const message = await prisma.message.findFirst({
        where: {
          type: 'SNAP',
          content: { contains: snapId },
          isDeleted: false,
        },
        select: {
          id: true,
          chatId: true,
          content: true,
        },
        orderBy: { createdAt: 'desc' },
      });

      if (!message || !message.content) {
        return null;
      }

      // Verify exact match by parsing the JSON content
      let parsedContent: SnapMessageContent;
      try {
        parsedContent = JSON.parse(message.content) as SnapMessageContent;
        if (parsedContent.snapId !== snapId) {
          return null;
        }
      } catch {
        return null;
      }

      // Update the message with the new status
      const updatedContent: SnapMessageContent = {
        ...parsedContent,
        status: newStatus,
      };

      const updatedMessage = await prisma.message.update({
        where: { id: message.id },
        data: {
          content: JSON.stringify(updatedContent),
        },
      });

      // Emit snap status update via WebSocket
      websocketService.emitSnapStatusUpdate(message.chatId, {
        chatId: message.chatId,
        messageId: message.id,
        snapId,
        status: newStatus,
        updatedAt: updatedMessage.updatedAt,
      });

      return {
        chatId: message.chatId,
        messageId: message.id,
        updatedAt: updatedMessage.updatedAt,
      };
    } catch (error) {
      // Log error instead of silently swallowing
      console.error(`Failed to update snap message status for snapId ${snapId}:`, error);
      throw error;
    }
  }

  /**
   * Create snap messages for multiple recipients
   * Returns array of created messages
   */
  async createSnapMessagesForRecipients(
    senderId: string,
    recipientIds: string[],
    snapId: string,
    mediaType: 'IMAGE' | 'VIDEO'
  ): Promise<void> {
    await Promise.all(
      recipientIds.map(async (recipientId) => {
        try {
          const chatId = await this.getOrCreateDirectChat(senderId, recipientId);
          await this.createSnapMessage(chatId, senderId, snapId, mediaType);
        } catch (error) {
          // Log but don't fail the whole operation
          console.error(`Failed to create snap message for recipient ${recipientId}:`, error);
        }
      })
    );
  }

  /**
   * Delete a chat for a specific user (soft delete)
   * Sets deletedAt on the user's ChatMember record
   * If all members have deleted, hard-delete the chat and messages
   */
  async deleteChat(chatId: string, userId: string): Promise<{ hardDeleted: boolean }> {
    // First verify the user is a member of this chat
    const member = await prisma.chatMember.findUnique({
      where: { chatId_userId: { chatId, userId } },
    });

    if (!member) {
      throw new Error('Not a member of this chat');
    }

    // Soft-delete: set leftAt and deletedAt for this user
    await prisma.chatMember.update({
      where: { chatId_userId: { chatId, userId } },
      data: {
        leftAt: new Date(),
        deletedAt: new Date(),
      },
    });

    // Check if all members have deleted the chat
    const remainingActiveMembers = await prisma.chatMember.count({
      where: {
        chatId,
        deletedAt: null,
      },
    });

    // If no active members remain, hard-delete the chat and its messages
    if (remainingActiveMembers === 0) {
      await prisma.$transaction([
        prisma.messageReadReceipt.deleteMany({
          where: { message: { chatId } },
        }),
        prisma.messageReaction.deleteMany({
          where: { message: { chatId } },
        }),
        prisma.message.deleteMany({
          where: { chatId },
        }),
        prisma.chatMember.deleteMany({
          where: { chatId },
        }),
        prisma.chat.delete({
          where: { id: chatId },
        }),
      ]);
      return { hardDeleted: true };
    }

    return { hardDeleted: false };
  }

  /**
   * Mark messages as delivered for a user
   * Creates/updates MessageReadReceipt records with deliveredAt timestamp
   */
  async markMessagesDelivered(
    chatId: string,
    messageIds: string[],
    userId: string
  ): Promise<{ deliveredCount: number; senderIds: string[] }> {
    // Verify user is a member of the chat
    const member = await prisma.chatMember.findUnique({
      where: { chatId_userId: { chatId, userId } },
    });

    if (!member || member.leftAt) {
      throw new Error('Not a member of this chat');
    }

    // Get messages that are NOT sent by the current user and belong to this chat
    const messages = await prisma.message.findMany({
      where: {
        id: { in: messageIds },
        chatId,
        senderId: { not: userId },
        isDeleted: false,
      },
      select: { id: true, senderId: true },
    });

    if (messages.length === 0) {
      return { deliveredCount: 0, senderIds: [] };
    }

    const now = new Date();
    const validMessageIds = messages.map(m => m.id);
    const senderIds = [...new Set(messages.map(m => m.senderId))];

    // Upsert delivery receipts for each message
    await Promise.all(
      validMessageIds.map((messageId) =>
        prisma.messageReadReceipt.upsert({
          where: { messageId_userId: { messageId, userId } },
          update: {
            deliveredAt: now,
          },
          create: {
            messageId,
            userId,
            deliveredAt: now,
          },
        })
      )
    );

    // Emit delivery notification via WebSocket
    websocketService.emitMessageDelivered(chatId, validMessageIds, userId);

    return { deliveredCount: validMessageIds.length, senderIds };
  }
}

export const chatService = new ChatService();