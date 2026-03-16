'use client';

import { useState, useCallback } from 'react';
import Link from 'next/link';
import { cn, formatCount } from '@/lib/utils';
import { Avatar } from '@/components/Avatar';
import { Button } from '@/components/Button';

export interface ProfileUser {
  id: string;
  display_name: string;
  handle: string;
  avatar_url?: string | null;
  bio?: string | null;
  follower_count: number;
  following_count: number;
  is_following?: boolean;
}

export interface ProfileCardProps {
  user: ProfileUser;
  onFollow?: (userId: string, follow: boolean) => void;
  /** Hide the follow button (e.g. when viewing own card) */
  hideFollow?: boolean;
  className?: string;
}

export function ProfileCard({ user, onFollow, hideFollow, className }: ProfileCardProps) {
  const [following, setFollowing] = useState(user.is_following ?? false);
  const [loading, setLoading] = useState(false);

  const handleFollow = useCallback(async () => {
    setLoading(true);
    const next = !following;
    setFollowing(next);
    try {
      onFollow?.(user.id, next);
    } finally {
      setLoading(false);
    }
  }, [following, onFollow, user.id]);

  const bioTruncated =
    user.bio && user.bio.length > 120 ? user.bio.slice(0, 120).trimEnd() + '...' : user.bio;

  return (
    <div
      className={cn(
        'rounded-xl border border-gray-200 bg-white p-4 transition-shadow hover:shadow-sm dark:border-gray-800 dark:bg-gray-950',
        className,
      )}
    >
      <div className="flex items-start gap-3">
        <Avatar
          src={user.avatar_url}
          alt={user.display_name}
          size="lg"
          href={`/profile/${user.handle}`}
        />

        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <Link
                href={`/profile/${user.handle}`}
                className="block truncate font-semibold text-gray-900 hover:underline dark:text-gray-100"
              >
                {user.display_name}
              </Link>
              <Link
                href={`/profile/${user.handle}`}
                className="block truncate text-sm text-gray-500 dark:text-gray-400"
              >
                @{user.handle}
              </Link>
            </div>

            {!hideFollow && (
              <Button
                variant={following ? 'secondary' : 'primary'}
                size="sm"
                loading={loading}
                onClick={handleFollow}
                aria-label={following ? `Unfollow ${user.display_name}` : `Follow ${user.display_name}`}
              >
                {following ? 'Following' : 'Follow'}
              </Button>
            )}
          </div>

          {bioTruncated && (
            <p className="mt-1.5 text-sm leading-snug text-gray-700 dark:text-gray-300">
              {bioTruncated}
            </p>
          )}

          <div className="mt-2 flex gap-4 text-sm">
            <Link
              href={`/profile/${user.handle}/followers`}
              className="text-gray-500 hover:underline dark:text-gray-400"
            >
              <span className="font-semibold text-gray-900 dark:text-gray-100">
                {formatCount(user.follower_count)}
              </span>{' '}
              followers
            </Link>
            <Link
              href={`/profile/${user.handle}/following`}
              className="text-gray-500 hover:underline dark:text-gray-400"
            >
              <span className="font-semibold text-gray-900 dark:text-gray-100">
                {formatCount(user.following_count)}
              </span>{' '}
              following
            </Link>
          </div>
        </div>
      </div>
    </div>
  );
}
