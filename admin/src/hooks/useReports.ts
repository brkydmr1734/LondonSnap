import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import api from '../services/api';
import toast from 'react-hot-toast';
import type { ReportsResponse, Report, ReportType } from '../types';

interface UseReportsParams {
  status?: string;
  limit?: number;
}

export function useReports({ status, limit = 50 }: UseReportsParams = {}) {
  return useQuery({
    queryKey: ['admin-reports', status],
    queryFn: async () => {
      const params: Record<string, any> = { limit };
      if (status && status !== 'ALL') params.status = status;
      const { data } = await api.get('/reports', { params });
      return data.data as ReportsResponse;
    },
  });
}

export function useResolveReport() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: ({ reportId, resolution = 'NO_ACTION' }: { reportId: string; resolution?: string }) =>
      api.patch(`/reports/${reportId}/resolve`, { resolution }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-reports'] });
      toast.success('Report resolved');
    },
    onError: () => {
      toast.error('Failed to resolve report');
    },
  });
}

export function useDismissReport() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: (reportId: string) => api.patch(`/reports/${reportId}/dismiss`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-reports'] });
      toast.success('Report dismissed');
    },
    onError: () => {
      toast.error('Failed to dismiss report');
    },
  });
}

export function getReportType(report: Report): ReportType {
  if (report.reportedUserId) return 'USER';
  if (report.reportedSnapId) return 'SNAP';
  if (report.reportedStoryId) return 'STORY';
  if (report.reportedMessageId) return 'MESSAGE';
  if (report.reportedEventId) return 'EVENT';
  return 'OTHER';
}
