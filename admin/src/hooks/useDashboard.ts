import { useQuery } from '@tanstack/react-query';
import api from '../services/api';
import type { DashboardStats, Activity } from '../types';

const REFETCH_INTERVAL = 30000; // 30 seconds

export function useDashboardStats() {
  return useQuery({
    queryKey: ['admin-stats'],
    queryFn: async () => {
      const { data } = await api.get('/dashboard/stats');
      return data.data.stats as DashboardStats;
    },
    refetchInterval: REFETCH_INTERVAL,
  });
}

export function useDashboardActivity() {
  return useQuery({
    queryKey: ['admin-activity'],
    queryFn: async () => {
      const { data } = await api.get('/dashboard/activity');
      return data.data.activity as Activity[];
    },
    refetchInterval: REFETCH_INTERVAL,
  });
}
