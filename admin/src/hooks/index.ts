// Dashboard hooks
export { useDashboardStats, useDashboardActivity } from './useDashboard';

// Users hooks
export { useUsers, useSuspendUser, useUnsuspendUser, useBanUser } from './useUsers';

// Reports hooks
export { useReports, useResolveReport, useDismissReport, getReportType } from './useReports';

// Events hooks
export { useEvents, useDeleteEvent, useUpdateEventStatus } from './useEvents';

// Universities hooks
export {
  useUniversities,
  useCreateUniversity,
  useUpdateUniversity,
  useDeleteUniversity,
  useToggleUniversityVerification,
} from './useUniversities';
