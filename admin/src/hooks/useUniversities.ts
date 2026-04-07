import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import api from '../services/api';
import toast from 'react-hot-toast';
import type { University, UniversityFormData } from '../types';

interface UseUniversitiesParams {
  search?: string;
  status?: string;
}

export function useUniversities({ search, status }: UseUniversitiesParams = {}) {
  return useQuery({
    queryKey: ['universities', search, status],
    queryFn: async () => {
      const params: Record<string, any> = {};
      if (search) params.q = search;
      if (status && status !== 'ALL') params.status = status;
      const res = await api.get('/universities', { params });
      return res.data.data.universities as University[];
    },
  });
}

export function useCreateUniversity() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: (payload: UniversityFormData) => api.post('/universities', payload),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['universities'] });
      toast.success('University created');
    },
    onError: () => {
      toast.error('Failed to create university');
    },
  });
}

export function useUpdateUniversity() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: ({ id, payload }: { id: string; payload: Partial<UniversityFormData & { isVerified: boolean }> }) =>
      api.put(`/universities/${id}`, payload),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['universities'] });
      toast.success('University updated');
    },
    onError: () => {
      toast.error('Failed to update university');
    },
  });
}

export function useDeleteUniversity() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: (id: string) => api.delete(`/universities/${id}`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['universities'] });
      toast.success('University deleted');
    },
    onError: () => {
      toast.error('Failed to delete university');
    },
  });
}

export function useToggleUniversityVerification() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: ({ id, isVerified }: { id: string; isVerified: boolean }) =>
      api.put(`/universities/${id}`, { isVerified }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['universities'] });
      toast.success('University verification updated');
    },
    onError: () => {
      toast.error('Failed to update verification status');
    },
  });
}
