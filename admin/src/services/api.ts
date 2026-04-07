import axios, { AxiosError, InternalAxiosRequestConfig } from 'axios';

const API_BASE = import.meta.env.VITE_API_URL || '/api/v1';

const api = axios.create({
  baseURL: `${API_BASE}/admin`,
  headers: { 'Content-Type': 'application/json' },
});

// Add auth token to every request
api.interceptors.request.use((config: InternalAxiosRequestConfig) => {
  try {
    const stored = localStorage.getItem('londonsnaps-admin-auth');
    if (stored) {
      const { state } = JSON.parse(stored);
      if (state?.token) {
        config.headers.Authorization = `Bearer ${state.token}`;
      }
    }
  } catch {}
  return config;
});

// Handle 401 responses
api.interceptors.response.use(
  (response: any) => response,
  (error: AxiosError) => {
    if (error.response?.status === 401) {
      localStorage.removeItem('londonsnaps-admin-auth');
      window.location.href = '/admin/login';
    }
    return Promise.reject(error);
  }
);

export default api;
