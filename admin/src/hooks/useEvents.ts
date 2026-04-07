import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import api from '../services/api';
import toast from 'react-hot-toast';
import type { EventsResponse } from '../types';

interface UseEventsParams {
  search?: string;
  status?: string;
  page?: number;
  limit?: number;
}

export function useEvents({ search, status, page = 1, limit = 20 }: UseEventsParams = {}) {
  return useQuery({
    queryKey: ['events', search, status, page],
    queryFn: async () => {
      const params: Record<string, any> = { page, limit };
      if (search) params.q = search;
      if (status && status !== 'ALL') params.status = status;
      const res = await api.get('/events', { params });
      return res.data.data as EventsResponse;
    },
  });
}

export function useDeleteEvent() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: (eventId: string) => api.delete(`/events/${eventId}`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['events'] });
      toast.success('Event deleted');
    },
    onError: () => {
      toast.error('Failed to delete event');
    },
  });
}

export function useUpdateEventStatus() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: ({ id, status }: { id: string; status: string }) =>
      api.patch(`/events/${id}/status`, { status }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['events'] });
      toast.success('Event status updated');
    },
    onError: () => {
      toast.error('Failed to update event status');
    },
  });
}
