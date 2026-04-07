import { UsersIcon, ChatBubbleLeftRightIcon, PhotoIcon, CalendarIcon, FlagIcon, FireIcon } from '@heroicons/react/24/outline';
import { formatDistanceToNow } from 'date-fns';
import { useDashboardStats, useDashboardActivity } from '../hooks';

export default function DashboardPage() {
  const { data: statsData, isLoading: statsLoading } = useDashboardStats();
  const { data: activityData } = useDashboardActivity();

  const stats = [
    { name: 'Total Users', value: statsData?.totalUsers ?? '-', icon: UsersIcon },
    { name: 'Active Chats', value: statsData?.activeChats ?? '-', icon: ChatBubbleLeftRightIcon },
    { name: 'Stories Today', value: statsData?.storiesToday ?? '-', icon: PhotoIcon },
    { name: 'Events This Week', value: statsData?.eventsThisWeek ?? '-', icon: CalendarIcon },
    { name: 'Pending Reports', value: statsData?.pendingReports ?? '-', icon: FlagIcon },
    { name: 'Active Streaks', value: statsData?.activeStreaks ?? '-', icon: FireIcon },
  ];

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-bold text-white">Dashboard</h1>
        <p className="text-gray-400 mt-1">Overview of LondonSnaps platform</p>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {stats.map((stat) => (
          <div key={stat.name} className="bg-surface rounded-xl p-6 border border-surface-variant">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-gray-400">{stat.name}</p>
                <p className="text-3xl font-bold text-white mt-1">
                  {statsLoading ? '...' : typeof stat.value === 'number' ? stat.value.toLocaleString() : stat.value}
                </p>
              </div>
              <div className="p-3 bg-primary/10 rounded-lg">
                <stat.icon className="w-6 h-6 text-primary" />
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Recent Activity */}
      <div className="bg-surface rounded-xl border border-surface-variant">
        <div className="px-6 py-4 border-b border-surface-variant">
          <h2 className="text-lg font-semibold text-white">Recent Activity</h2>
        </div>
        <div className="p-6">
          <div className="space-y-4">
            {(activityData || []).slice(0, 10).map((item) => (
              <div key={item.id + item.type} className="flex items-center justify-between py-3 border-b border-surface-variant last:border-0">
                <div className="flex items-center gap-4">
                  <div className={`w-10 h-10 rounded-full flex items-center justify-center ${
                    item.type === 'USER_JOINED' ? 'bg-green-500/20' :
                    item.type === 'REPORT' ? 'bg-red-500/20' : 'bg-blue-500/20'
                  }`}>
                    <span className={`text-sm font-semibold ${
                      item.type === 'USER_JOINED' ? 'text-green-400' :
                      item.type === 'REPORT' ? 'text-red-400' : 'text-blue-400'
                    }`}>
                      {item.type === 'USER_JOINED' ? 'U' : item.type === 'REPORT' ? 'R' : 'E'}
                    </span>
                  </div>
                  <div>
                    <p className="text-white font-medium text-sm">{item.description}</p>
                    <p className="text-xs text-gray-400">{formatDistanceToNow(new Date(item.createdAt), { addSuffix: true })}</p>
                  </div>
                </div>
              </div>
            ))}
            {!activityData?.length && (
              <p className="text-gray-500 text-center py-4">No recent activity</p>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
