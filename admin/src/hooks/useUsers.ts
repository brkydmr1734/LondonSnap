import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import api from '../services/api';
import toast from 'react-hot-toast';
import type { User, UsersResponse } from '../types';

interface UseUsersParams {
  search?: string;
  status?: string;
  page?: number;
  limit?: number;
}

export function useUsers({ search, status, page = 1, limit = 20 }: UseUsersParams = {}) {
  return useQuery({
    queryKey: ['admin-users', search, status, page],
    queryFn: async () => {
      const params: Record<string, any> = { page, limit };
      if (search) params.q = search;
      if (status) params.status = status;
      const { data } = await api.get('/users', { params });
      return data.data as UsersResponse;
    },
  });
}

export function useSuspendUser() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: ({ userId, reason = 'Admin action', days = 7 }: { userId: string; reason?: string; days?: number }) =>
      api.post(`/users/${userId}/suspend`, { reason, days }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-users'] });
      toast.success('User suspended');
    },
    onError: () => {
      toast.error('Failed to suspend user');
    },
  });
}

export function useUnsuspendUser() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: (userId: string) => api.post(`/users/${userId}/unsuspend`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-users'] });
      toast.success('User unsuspended');
    },
    onError: () => {
      toast.error('Failed to unsuspend user');
    },
  });
}

export function useBanUser() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: ({ userId, reason = 'Admin action' }: { userId: string; reason?: string }) =>
      api.post(`/users/${userId}/ban`, { reason }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-users'] });
      toast.success('User banned');
    },
    onError: () => {
      toast.error('Failed to ban user');
    },
  });
}
