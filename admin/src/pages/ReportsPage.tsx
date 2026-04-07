import { useState } from 'react';
import { CheckCircleIcon, XCircleIcon, EyeIcon } from '@heroicons/react/24/outline';
import { useReports, useResolveReport, useDismissReport, getReportType } from '../hooks';
import type { Report } from '../types';

export function ReportsPage() {
  const [statusFilter, setStatusFilter] = useState('ALL');
  const [selectedReport, setSelectedReport] = useState<Report | null>(null);

  const { data, isLoading } = useReports({ status: statusFilter });
  const resolveMutation = useResolveReport();
  const dismissMutation = useDismissReport();

  const handleResolve = (reportId: string) => {
    resolveMutation.mutate({ reportId }, {
      onSuccess: () => setSelectedReport(null),
    });
  };

  const handleDismiss = (reportId: string) => {
    dismissMutation.mutate(reportId, {
      onSuccess: () => setSelectedReport(null),
    });
  };

  const getStatusColor = (s: string) => {
    switch (s) {
      case 'PENDING': return 'bg-yellow-500/20 text-yellow-400';
      case 'RESOLVED': return 'bg-green-500/20 text-green-400';
      case 'DISMISSED': return 'bg-gray-500/20 text-gray-400';
      default: return 'bg-blue-500/20 text-blue-400';
    }
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold text-white">Reports</h1>
        <p className="text-gray-400 mt-1">Content moderation {data ? `(${data.total} total)` : ''}</p>
      </div>

      <div className="flex gap-4">
        {['ALL', 'PENDING', 'RESOLVED', 'DISMISSED'].map(s => (
          <button key={s} onClick={() => setStatusFilter(s)}
            className={`px-4 py-2 rounded-lg text-sm font-medium ${statusFilter === s ? 'bg-primary text-black' : 'bg-surface text-gray-400 border border-surface-variant'}`}>
            {s === 'ALL' ? 'All' : s.charAt(0) + s.slice(1).toLowerCase()}
          </button>
        ))}
      </div>

      <div className="bg-surface rounded-xl border border-surface-variant overflow-hidden">
        {isLoading ? (
          <div className="p-8 text-center text-gray-400">Loading reports...</div>
        ) : (
          <table className="w-full">
            <thead className="bg-surface-variant">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-semibold text-gray-300 uppercase">Type</th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-gray-300 uppercase">Reason</th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-gray-300 uppercase">Reporter</th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-gray-300 uppercase">Reported</th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-gray-300 uppercase">Status</th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-gray-300 uppercase">Date</th>
                <th className="px-6 py-3 text-right text-xs font-semibold text-gray-300 uppercase">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-surface-variant">
              {(data?.reports || []).map((report) => (
                <tr key={report.id} className="hover:bg-surface-variant/50">
                  <td className="px-6 py-4 text-sm text-gray-300">{getReportType(report)}</td>
                  <td className="px-6 py-4">
                    <div className="text-sm font-medium text-white">{report.reason}</div>
                    {report.description && <div className="text-xs text-gray-400 truncate max-w-xs">{report.description}</div>}
                  </td>
                  <td className="px-6 py-4 text-sm text-gray-300">{report.author.displayName}</td>
                  <td className="px-6 py-4 text-sm text-gray-300">{report.reportedUser?.displayName || '-'}</td>
                  <td className="px-6 py-4">
                    <span className={`px-2 py-1 text-xs font-medium rounded-full ${getStatusColor(report.status)}`}>{report.status}</span>
                  </td>
                  <td className="px-6 py-4 text-sm text-gray-400">{new Date(report.createdAt).toLocaleDateString()}</td>
                  <td className="px-6 py-4 text-right">
                    <div className="flex items-center justify-end gap-2">
                      <button onClick={() => setSelectedReport(report)} className="p-1 text-gray-400 hover:text-blue-400"><EyeIcon className="w-5 h-5" /></button>
                      {report.status === 'PENDING' && (
                        <>
                          <button onClick={() => handleResolve(report.id)} className="p-1 text-gray-400 hover:text-green-400"><CheckCircleIcon className="w-5 h-5" /></button>
                          <button onClick={() => handleDismiss(report.id)} className="p-1 text-gray-400 hover:text-red-400"><XCircleIcon className="w-5 h-5" /></button>
                        </>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* Detail Modal */}
      {selectedReport && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setSelectedReport(null)}>
          <div className="bg-surface rounded-xl p-6 max-w-lg w-full mx-4" onClick={e => e.stopPropagation()}>
            <h3 className="text-lg font-semibold text-white mb-4">Report Details</h3>
            <div className="space-y-3 text-sm">
              <div><span className="text-gray-400">Type:</span> <span className="text-white ml-2">{getReportType(selectedReport)}</span></div>
              <div><span className="text-gray-400">Reason:</span> <span className="text-white ml-2">{selectedReport.reason}</span></div>
              <div><span className="text-gray-400">Description:</span> <span className="text-white ml-2">{selectedReport.description || 'N/A'}</span></div>
              <div><span className="text-gray-400">Reporter:</span> <span className="text-white ml-2">{selectedReport.author.displayName} (@{selectedReport.author.username})</span></div>
              <div><span className="text-gray-400">Status:</span> <span className={`ml-2 px-2 py-1 rounded-full text-xs ${getStatusColor(selectedReport.status)}`}>{selectedReport.status}</span></div>
              <div><span className="text-gray-400">Date:</span> <span className="text-white ml-2">{new Date(selectedReport.createdAt).toLocaleString()}</span></div>
            </div>
            <div className="flex justify-end gap-3 mt-6">
              {selectedReport.status === 'PENDING' && (
                <>
                  <button onClick={() => handleResolve(selectedReport.id)} className="px-4 py-2 bg-green-600 text-white rounded-lg text-sm">Resolve</button>
                  <button onClick={() => handleDismiss(selectedReport.id)} className="px-4 py-2 bg-red-600 text-white rounded-lg text-sm">Dismiss</button>
                </>
              )}
              <button onClick={() => setSelectedReport(null)} className="px-4 py-2 bg-surface-variant text-white rounded-lg text-sm">Close</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default ReportsPage;
