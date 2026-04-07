// User Types
export interface User {
  id: string;
  email: string;
  username: string;
  displayName: string;
  avatarUrl: string | null;
  isVerified: boolean;
  isUniversityStudent: boolean;
  isAdmin: boolean;
  status: string;
  createdAt: string;
  lastSeenAt: string;
  university: { id: string; shortName: string; name: string } | null;
}

export interface UsersResponse {
  users: User[];
  total: number;
  totalPages: number;
}

export type UserStatus = 'ACTIVE' | 'SUSPENDED' | 'DELETED';

// Report Types
export interface Report {
  id: string;
  reason: string;
  description: string | null;
  status: string;
  reportedUserId: string | null;
  reportedSnapId: string | null;
  reportedStoryId: string | null;
  reportedMessageId: string | null;
  reportedEventId: string | null;
  createdAt: string;
  reviewedAt: string | null;
  reviewedBy: string | null;
  resolution: string | null;
  reviewNotes: string | null;
  author: { id: string; username: string; displayName: string };
  reportedUser: { id: string; username: string; displayName: string } | null;
}

export interface ReportsResponse {
  reports: Report[];
  total: number;
}

export type ReportStatus = 'ALL' | 'PENDING' | 'RESOLVED' | 'DISMISSED';

export type ReportType = 'USER' | 'SNAP' | 'STORY' | 'MESSAGE' | 'EVENT' | 'OTHER';

// Event Types
export interface EventItem {
  id: string;
  title: string;
  description: string | null;
  location: string | null;
  latitude: number | null;
  longitude: number | null;
  startDate: string;
  endDate: string | null;
  category: string;
  status: string;
  createdAt: string;
  creator: { id: string; displayName: string; avatarUrl: string | null };
  university: { id: string; shortName: string } | null;
  _count: { rsvps: number };
}

export interface EventsResponse {
  events: EventItem[];
  total: number;
  page: number;
  totalPages: number;
}

export type EventStatus = 'ALL' | 'DRAFT' | 'ACTIVE' | 'CANCELLED' | 'COMPLETED';

export type EventCategory = 'SOCIAL' | 'ACADEMIC' | 'SPORTS' | 'ARTS' | 'CAREER' | 'OTHER';

// University Types
export interface University {
  id: string;
  name: string;
  shortName: string;
  domain: string;
  location: string | null;
  logoUrl: string | null;
  isVerified: boolean;
  createdAt: string;
  _count: { users: number; circles: number; events: number };
}

export interface UniversityFormData {
  name: string;
  shortName: string;
  domain: string;
  location: string;
}

// Dashboard Types
export interface DashboardStats {
  totalUsers: number;
  activeUsers: number;
  newUsers: number;
  totalChats: number;
  activeChats: number;
  storiesToday: number;
  snapsToday: number;
  pendingReports: number;
  activeStreaks: number;
  eventsThisWeek: number;
}

export interface Activity {
  id: string;
  type: string;
  description: string;
  createdAt: string;
}

export type ActivityType = 'USER_JOINED' | 'REPORT' | 'EVENT';

// Common Types
export interface PaginationParams {
  page?: number;
  limit?: number;
  q?: string;
}
