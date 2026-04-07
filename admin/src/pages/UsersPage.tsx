import { useState } from 'react';
import { useUsers, useSuspendUser, useUnsuspendUser, useBanUser } from '../hooks';
import type { User } from '../types';

export default function UsersPage() {
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [page, setPage] = useState(1);

  const { data, isLoading } = useUsers({ search, status: statusFilter, page });
  const suspendMutation = useSuspendUser();
  const unsuspendMutation = useUnsuspendUser();
  const banMutation = useBanUser();

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'ACTIVE': return 'bg-success/20 text-success';
      case 'SUSPENDED': return 'bg-warning/20 text-warning';
      case 'DELETED': return 'bg-error/20 text-error';
      default: return 'bg-gray-500/20 text-gray-400';
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-3xl font-bold text-white">Users</h1>
          <p className="text-gray-400 mt-1">Manage platform users {data ? `(${data.total} total)` : ''}</p>
        </div>
      </div>

      {/* Filters */}
      <div className="flex gap-4">
        <input
          type="text"
          placeholder="Search users..."
          value={search}
          onChange={(e) => { setSearch(e.target.value); setPage(1); }}
          className="flex-1 px-4 py-2 bg-surface border border-surface-variant rounded-lg text-white"
        />
        <select
          value={statusFilter}
          onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }}
          className="px-4 py-2 bg-surface border border-surface-variant rounded-lg text-white"
        >
          <option value="">All Status</option>
          <option value="ACTIVE">Active</option>
          <option value="SUSPENDED">Suspended</option>
          <option value="DELETED">Banned</option>
        </select>
      </div>

      {/* Users Table */}
      <div className="bg-surface rounded-xl border border-surface-variant overflow-hidden">
        {isLoading ? (
          <div className="p-8 text-center text-gray-400">Loading users...</div>
        ) : (
          <table className="w-full">
            <thead className="bg-surface-variant">
              <tr>
                <th className="px-6 py-4 text-left text-sm font-semibold text-gray-300">User</th>
                <th className="px-6 py-4 text-left text-sm font-semibold text-gray-300">Email</th>
                <th className="px-6 py-4 text-left text-sm font-semibold text-gray-300">University</th>
                <th className="px-6 py-4 text-left text-sm font-semibold text-gray-300">Status</th>
                <th className="px-6 py-4 text-left text-sm font-semibold text-gray-300">Joined</th>
                <th className="px-6 py-4 text-left text-sm font-semibold text-gray-300">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-surface-variant">
              {(data?.users || []).map((user) => (
                <tr key={user.id} className="hover:bg-surface-variant/50">
                  <td className="px-6 py-4">
                    <div className="flex items-center gap-3">
                      <div className="w-10 h-10 rounded-full bg-primary/20 flex items-center justify-center">
                        {user.avatarUrl ? (
                          <img src={user.avatarUrl} alt="" className="w-10 h-10 rounded-full object-cover" />
                        ) : (
                          <span className="text-primary font-semibold">{user.displayName.charAt(0)}</span>
                        )}
                      </div>
                      <div>
                        <p className="text-white font-medium">{user.displayName} {user.isAdmin && <span className="text-xs text-primary">(Admin)</span>}</p>
                        <p className="text-sm text-gray-400">@{user.username}</p>
                      </div>
                    </div>
                  </td>
                  <td className="px-6 py-4 text-gray-300 text-sm">{user.email}</td>
                  <td className="px-6 py-4 text-gray-300 text-sm">{user.university?.shortName || '-'}</td>
                  <td className="px-6 py-4">
                    <span className={`px-2 py-1 text-xs font-medium rounded-full ${getStatusBadge(user.status)}`}>
                      {user.status}
                    </span>
                  </td>
                  <td className="px-6 py-4 text-gray-400 text-sm">
                    {new Date(user.createdAt).toLocaleDateString()}
                  </td>
                  <td className="px-6 py-4">
                    <div className="flex gap-2">
                      {user.status === 'ACTIVE' && (
                        <button onClick={() => suspendMutation.mutate({ userId: user.id })} className="text-warning hover:underline text-sm">Suspend</button>
                      )}
                      {user.status === 'SUSPENDED' && (
                        <button onClick={() => unsuspendMutation.mutate(user.id)} className="text-success hover:underline text-sm">Unsuspend</button>
                      )}
                      {user.status !== 'DELETED' && (
                        <button onClick={() => { if (confirm('Ban this user?')) banMutation.mutate({ userId: user.id }); }} className="text-error hover:underline text-sm">Ban</button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* Pagination */}
      {data && data.totalPages > 1 && (
        <div className="flex justify-center gap-2">
          <button disabled={page <= 1} onClick={() => setPage(p => p - 1)} className="px-4 py-2 bg-surface border border-surface-variant rounded-lg text-white disabled:opacity-50">Previous</button>
          <span className="px-4 py-2 text-gray-400">Page {page} of {data.totalPages}</span>
          <button disabled={page >= data.totalPages} onClick={() => setPage(p => p + 1)} className="px-4 py-2 bg-surface border border-surface-variant rounded-lg text-white disabled:opacity-50">Next</button>
        </div>
      )}
    </div>
  );
}
