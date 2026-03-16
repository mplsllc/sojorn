'use client';

import { useState, useCallback } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { api } from '@/lib/api';
import { useAuth } from '@/lib/auth';
import { PostCard } from '@/components/PostCard';
import { LoadingSpinner } from '@/components/LoadingSpinner';
import { EmptyState } from '@/components/EmptyState';
import { InfiniteScroll } from '@/components/InfiniteScroll';
import { Button } from '@/components/Button';
import { Calendar, LinkIcon, MapPin, Settings } from 'lucide-react';

interface Profile {
  id: string;
  handle: string;
  display_name: string;
  bio: string;
  avatar_url: string;
  header_url?: string;
  follower_count: number;
  following_count: number;
  post_count: number;
  created_at: string;
  fields?: Array<{ name: string; value: string; verified_at?: string }>;
  is_following?: boolean;
  is_self?: boolean;
}

interface Post {
  id: string;
  content: string;
  author: {
    id: string;
    handle: string;
    display_name: string;
    avatar_url: string;
  };
  media: Array<{
    id: string;
    url: string;
    type: string;
    alt_text?: string;
  }>;
  like_count: number;
  reply_count: number;
  repost_count: number;
  liked: boolean;
  reposted: boolean;
  bookmarked: boolean;
  created_at: string;
  visibility: string;
}

type Tab = 'posts' | 'replies' | 'media' | 'likes';

const tabs: { key: Tab; label: string }[] = [
  { key: 'posts', label: 'Posts' },
  { key: 'replies', label: 'Replies' },
  { key: 'media', label: 'Media' },
  { key: 'likes', label: 'Likes' },
];

export default function ProfileContent({ profile }: { profile: Profile }) {
  const { user } = useAuth();
  const [activeTab, setActiveTab] = useState<Tab>('posts');
  const [posts, setPosts] = useState<Post[]>([]);
  const [cursor, setCursor] = useState<string | undefined>(undefined);
  const [hasMore, setHasMore] = useState(true);
  const [isLoading, setIsLoading] = useState(true);
  const [isFollowing, setIsFollowing] = useState(profile.is_following ?? false);
  const [followLoading, setFollowLoading] = useState(false);
  const [followerCount, setFollowerCount] = useState(profile.follower_count);

  const loadPosts = useCallback(
    async (tab: Tab, loadCursor?: string) => {
      try {
        const data = await api.getProfileByHandle(profile.handle, {
          tab,
          cursor: loadCursor,
        });
        const newPosts: Post[] = data.posts ?? [];
        if (loadCursor) {
          setPosts((prev) => [...prev, ...newPosts]);
        } else {
          setPosts(newPosts);
        }
        setCursor(data.next_cursor);
        setHasMore(!!data.next_cursor);
      } catch {
        setHasMore(false);
      } finally {
        setIsLoading(false);
      }
    },
    [profile.handle]
  );

  const switchTab = (tab: Tab) => {
    setActiveTab(tab);
    setPosts([]);
    setCursor(undefined);
    setHasMore(true);
    setIsLoading(true);
    loadPosts(tab);
  };

  const loadMore = useCallback(() => {
    if (cursor && hasMore) {
      loadPosts(activeTab, cursor);
    }
  }, [cursor, hasMore, activeTab, loadPosts]);

  // Initial load
  useState(() => {
    loadPosts('posts');
  });

  const handleFollow = async () => {
    setFollowLoading(true);
    try {
      if (isFollowing) {
        await api.unfollowUser(profile.id);
        setIsFollowing(false);
        setFollowerCount((c) => c - 1);
      } else {
        await api.followUser(profile.id);
        setIsFollowing(true);
        setFollowerCount((c) => c + 1);
      }
    } catch {
      // Revert on failure handled by not updating state
    } finally {
      setFollowLoading(false);
    }
  };

  const isSelf = profile.is_self || user?.handle === profile.handle;
  const joinDate = new Date(profile.created_at).toLocaleDateString('en-US', {
    month: 'long',
    year: 'numeric',
  });

  return (
    <main className="mx-auto max-w-2xl">
      {/* Header image */}
      <div className="relative h-32 sm:h-48 bg-brand-200 dark:bg-brand-900">
        {profile.header_url && (
          <Image
            src={profile.header_url}
            alt=""
            fill
            className="object-cover"
            priority
          />
        )}
      </div>

      {/* Profile info */}
      <div className="px-4 pb-4">
        <div className="flex items-end justify-between -mt-12 sm:-mt-16 mb-4">
          <div className="relative h-24 w-24 sm:h-32 sm:w-32 rounded-full border-4 border-white dark:border-gray-950 overflow-hidden bg-gray-200 dark:bg-gray-800">
            {profile.avatar_url ? (
              <Image
                src={profile.avatar_url}
                alt={`${profile.display_name || profile.handle}'s avatar`}
                fill
                className="object-cover"
                priority
              />
            ) : (
              <div className="flex h-full w-full items-center justify-center text-3xl font-bold text-gray-400">
                {(profile.display_name || profile.handle)[0]?.toUpperCase()}
              </div>
            )}
          </div>

          <div className="flex items-center gap-2 mt-14 sm:mt-18">
            {isSelf ? (
              <Link
                href="/settings"
                className="inline-flex items-center gap-1.5 rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 px-4 py-2 text-sm font-medium text-gray-900 dark:text-gray-100 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600"
              >
                <Settings className="h-4 w-4" aria-hidden="true" />
                Edit profile
              </Link>
            ) : (
              <Button
                onClick={handleFollow}
                disabled={followLoading}
                variant={isFollowing ? 'secondary' : 'primary'}
                aria-label={
                  isFollowing
                    ? `Unfollow @${profile.handle}`
                    : `Follow @${profile.handle}`
                }
              >
                {followLoading ? (
                  <LoadingSpinner />
                ) : isFollowing ? (
                  'Following'
                ) : (
                  'Follow'
                )}
              </Button>
            )}
          </div>
        </div>

        <div>
          <h1 className="text-xl font-bold text-gray-900 dark:text-gray-50">
            {profile.display_name || profile.handle}
          </h1>
          <p className="text-sm text-gray-500 dark:text-gray-400">
            @{profile.handle}
          </p>
        </div>

        {profile.bio && (
          <p className="mt-3 text-sm text-gray-700 dark:text-gray-300 whitespace-pre-line leading-relaxed">
            {profile.bio}
          </p>
        )}

        {profile.fields && profile.fields.length > 0 && (
          <div className="mt-3 space-y-1">
            {profile.fields.map((field, i) => (
              <div key={i} className="flex items-center gap-2 text-sm">
                <span className="text-gray-500 dark:text-gray-400 font-medium">
                  {field.name}:
                </span>
                <span
                  className={`${field.verified_at ? 'text-green-600 dark:text-green-400' : 'text-gray-700 dark:text-gray-300'}`}
                  dangerouslySetInnerHTML={{ __html: field.value }}
                />
              </div>
            ))}
          </div>
        )}

        <div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-gray-500 dark:text-gray-400">
          <span className="inline-flex items-center gap-1">
            <Calendar className="h-4 w-4" aria-hidden="true" />
            Joined {joinDate}
          </span>
        </div>

        <div className="mt-3 flex items-center gap-4 text-sm">
          <Link
            href={`/profile/${profile.handle}/following`}
            className="hover:underline"
          >
            <span className="font-semibold text-gray-900 dark:text-gray-100">
              {profile.following_count.toLocaleString()}
            </span>{' '}
            <span className="text-gray-500 dark:text-gray-400">Following</span>
          </Link>
          <Link
            href={`/profile/${profile.handle}/followers`}
            className="hover:underline"
          >
            <span className="font-semibold text-gray-900 dark:text-gray-100">
              {followerCount.toLocaleString()}
            </span>{' '}
            <span className="text-gray-500 dark:text-gray-400">Followers</span>
          </Link>
        </div>
      </div>

      {/* Tabs */}
      <div
        className="border-b border-gray-200 dark:border-gray-800"
        role="tablist"
        aria-label="Profile content tabs"
      >
        <div className="flex">
          {tabs.map((tab) => (
            <button
              key={tab.key}
              role="tab"
              aria-selected={activeTab === tab.key}
              aria-controls={`tabpanel-${tab.key}`}
              onClick={() => switchTab(tab.key)}
              className={`flex-1 px-4 py-3 text-sm font-medium text-center border-b-2 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-brand-600 ${
                activeTab === tab.key
                  ? 'border-brand-600 text-brand-600 dark:border-brand-400 dark:text-brand-400'
                  : 'border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300 hover:border-gray-300 dark:hover:border-gray-600'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      {/* Tab content */}
      <div
        id={`tabpanel-${activeTab}`}
        role="tabpanel"
        aria-label={`${activeTab} content`}
        className="px-4 py-4"
      >
        {isLoading ? (
          <div className="flex justify-center py-12">
            <LoadingSpinner />
          </div>
        ) : posts.length === 0 ? (
          <EmptyState
            title={`No ${activeTab} yet`}
            description={
              isSelf
                ? `Your ${activeTab} will appear here.`
                : `@${profile.handle} hasn't posted any ${activeTab} yet.`
            }
          />
        ) : (
          <InfiniteScroll onLoadMore={loadMore} hasMore={hasMore}>
            <div className="space-y-4" role="feed" aria-label={`${activeTab} by @${profile.handle}`}>
              {posts.map((post) => (
                <PostCard key={post.id} post={post} />
              ))}
            </div>
          </InfiniteScroll>
        )}
      </div>
    </main>
  );
}
