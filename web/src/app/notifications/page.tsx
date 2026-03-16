'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import Image from 'next/image';
import { api } from '@/lib/api';
import { useAuth } from '@/lib/auth';
import { Nav } from '@/components/Nav';
import { LoadingSpinner } from '@/components/LoadingSpinner';
import { EmptyState } from '@/components/EmptyState';
import { InfiniteScroll } from '@/components/InfiniteScroll';
import {
  Heart,
  MessageCircle,
  UserPlus,
  AtSign,
  Repeat2,
  Bell,
  CheckCheck,
} from 'lucide-react';

interface NotificationAccount {
  id: string;
  handle: string;
  display_name: string;
  avatar_url: string;
}

interface NotificationPost {
  id: string;
  content: string;
}

interface Notification {
  id: string;
  type: 'like' | 'reply' | 'follow' | 'mention' | 'repost' | 'poll' | 'follow_request';
  account: NotificationAccount;
  post?: NotificationPost;
  read: boolean;
  created_at: string;
}

interface NotificationsResponse {
  notifications: Notification[];
  next_cursor?: string;
}

const notificationIcons: Record<Notification['type'], React.ElementType> = {
  like: Heart,
  reply: MessageCircle,
  follow: UserPlus,
  mention: AtSign,
  repost: Repeat2,
  poll: Bell,
  follow_request: UserPlus,
};

const notificationColors: Record<Notification['type'], string> = {
  like: 'text-red-500',
  reply: 'text-blue-500',
  follow: 'text-brand-500',
  mention: 'text-amber-500',
  repost: 'text-green-500',
  poll: 'text-purple-500',
  follow_request: 'text-brand-500',
};

function notificationText(notification: Notification): string {
  const name = notification.account.display_name || `@${notification.account.handle}`;
  switch (notification.type) {
    case 'like':
      return `${name} liked your post`;
    case 'reply':
      return `${name} replied to your post`;
    case 'follow':
      return `${name} followed you`;
    case 'mention':
      return `${name} mentioned you`;
    case 'repost':
      return `${name} reposted your post`;
    case 'poll':
      return `A poll you voted in has ended`;
    case 'follow_request':
      return `${name} requested to follow you`;
    default:
      return `${name} interacted with you`;
  }
}

function timeAgo(dateStr: string): string {
  const seconds = Math.floor(
    (Date.now() - new Date(dateStr).getTime()) / 1000
  );
  if (seconds < 60) return 'just now';
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d`;
  return new Date(dateStr).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
  });
}

export default function NotificationsPage() {
  const { user, isLoading: authLoading } = useAuth();
  const router = useRouter();
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [cursor, setCursor] = useState<string | undefined>(undefined);
  const [hasMore, setHasMore] = useState(true);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!authLoading && !user) {
      router.replace('/auth/login');
    }
  }, [user, authLoading, router]);

  const loadNotifications = useCallback(async (loadCursor?: string) => {
    try {
      setError(null);
      const data: NotificationsResponse = await api.getNotifications({
        cursor: loadCursor,
      });
      if (loadCursor) {
        setNotifications((prev) => [...prev, ...data.notifications]);
      } else {
        setNotifications(data.notifications);
      }
      setCursor(data.next_cursor);
      setHasMore(!!data.next_cursor);
    } catch {
      setError('Failed to load notifications.');
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    if (user) {
      loadNotifications();
      // Mark as read on page view
      api.markNotificationsRead().catch(() => {});
    }
  }, [user, loadNotifications]);

  const loadMore = useCallback(() => {
    if (cursor && hasMore) {
      loadNotifications(cursor);
    }
  }, [cursor, hasMore, loadNotifications]);

  const markAllRead = async () => {
    try {
      await api.markNotificationsRead();
      setNotifications((prev) => prev.map((n) => ({ ...n, read: true })));
    } catch {
      // Silent fail
    }
  };

  if (authLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <LoadingSpinner />
      </div>
    );
  }

  if (!user) return null;

  const unreadCount = notifications.filter((n) => !n.read).length;

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      <Nav />
      <main className="mx-auto max-w-2xl px-4 py-6">
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-50">
            Notifications
          </h1>
          {unreadCount > 0 && (
            <button
              onClick={markAllRead}
              className="inline-flex items-center gap-1.5 text-sm font-medium text-brand-600 dark:text-brand-400 hover:text-brand-700 dark:hover:text-brand-300 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600"
              aria-label={`Mark all ${unreadCount} notifications as read`}
            >
              <CheckCheck className="h-4 w-4" aria-hidden="true" />
              Mark all read
            </button>
          )}
        </div>

        {isLoading ? (
          <div className="flex justify-center py-12">
            <LoadingSpinner />
          </div>
        ) : error ? (
          <div
            className="rounded-xl border border-red-200 dark:border-red-900 bg-red-50 dark:bg-red-950/50 p-6 text-center"
            role="alert"
          >
            <p className="text-red-700 dark:text-red-400">{error}</p>
            <button
              onClick={() => {
                setIsLoading(true);
                loadNotifications();
              }}
              className="mt-3 text-sm font-medium text-red-600 dark:text-red-400 hover:underline"
            >
              Try again
            </button>
          </div>
        ) : notifications.length === 0 ? (
          <EmptyState
            title="No notifications yet"
            description="When someone interacts with your posts or follows you, it will show up here."
          />
        ) : (
          <InfiniteScroll onLoadMore={loadMore} hasMore={hasMore}>
            <div
              className="rounded-xl border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 divide-y divide-gray-100 dark:divide-gray-800 overflow-hidden"
              role="list"
              aria-label="Notifications"
            >
              {notifications.map((notification) => {
                const Icon = notificationIcons[notification.type];
                const iconColor = notificationColors[notification.type];
                const href = notification.post
                  ? `/post/${notification.post.id}`
                  : `/profile/${notification.account.handle}`;

                return (
                  <Link
                    key={notification.id}
                    href={href}
                    className={`flex items-start gap-3 p-4 hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-brand-600 ${
                      !notification.read
                        ? 'bg-brand-50/50 dark:bg-brand-950/20'
                        : ''
                    }`}
                    role="listitem"
                  >
                    <div className="relative flex-shrink-0">
                      <div className="relative h-10 w-10 rounded-full overflow-hidden bg-gray-200 dark:bg-gray-800">
                        {notification.account.avatar_url ? (
                          <Image
                            src={notification.account.avatar_url}
                            alt=""
                            fill
                            className="object-cover"
                          />
                        ) : (
                          <span className="flex h-full w-full items-center justify-center text-sm font-bold text-gray-400">
                            {(notification.account.display_name || notification.account.handle)[0]?.toUpperCase()}
                          </span>
                        )}
                      </div>
                      <div
                        className={`absolute -bottom-1 -right-1 flex h-5 w-5 items-center justify-center rounded-full bg-white dark:bg-gray-900 ${iconColor}`}
                      >
                        <Icon className="h-3.5 w-3.5" aria-hidden="true" />
                      </div>
                    </div>

                    <div className="flex-1 min-w-0">
                      <p className="text-sm text-gray-900 dark:text-gray-100">
                        {notificationText(notification)}
                      </p>
                      {notification.post && (
                        <p className="mt-1 text-sm text-gray-500 dark:text-gray-400 truncate">
                          {notification.post.content.replace(/<[^>]*>/g, '')}
                        </p>
                      )}
                      <p className="mt-1 text-xs text-gray-400 dark:text-gray-500">
                        {timeAgo(notification.created_at)}
                      </p>
                    </div>

                    {!notification.read && (
                      <div
                        className="mt-2 h-2 w-2 rounded-full bg-brand-500 flex-shrink-0"
                        aria-label="Unread"
                      />
                    )}
                  </Link>
                );
              })}
            </div>
          </InfiniteScroll>
        )}
      </main>
    </div>
  );
}
