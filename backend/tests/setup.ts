import { beforeAll, afterAll } from 'vitest';
import { prisma } from '../src/lib/prisma';
import { redis } from '../src/lib/redis';

beforeAll(async () => {
  // Ensure we're using test database
  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl?.includes('test')) {
    throw new Error('Tests must run against test database');
  }
  
  // Connect to database
  await prisma.$connect();
  
  // Connect to Redis
  await redis.connect();
  
  console.log('Test environment setup complete');
});

afterAll(async () => {
  // Cleanup all data
  await prisma.notification.deleteMany();
  await prisma.storyView.deleteMany();
  await prisma.storyReaction.deleteMany();
  await prisma.story.deleteMany();
  await prisma.snap.deleteMany();
  await prisma.message.deleteMany();
  await prisma.chatMember.deleteMany();
  await prisma.chat.deleteMany();
  await prisma.eventRSVP.deleteMany();
  await prisma.event.deleteMany();
  await prisma.circleMember.deleteMany();
  await prisma.circle.deleteMany();
  await prisma.streak.deleteMany();
  await prisma.block.deleteMany();
  await prisma.friendship.deleteMany();
  await prisma.friendRequest.deleteMany();
  await prisma.report.deleteMany();
  await prisma.verificationCode.deleteMany();
  await prisma.session.deleteMany();
  await prisma.user.deleteMany();
  await prisma.university.deleteMany();
  
  // Disconnect
  await prisma.$disconnect();
  await redis.quit();
  
  console.log('Test environment cleanup complete');
});
