'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { api } from '@/lib/api';
import { useAuth } from '@/lib/auth';
import { Nav } from '@/components/Nav';
import { PostCard } from '@/components/PostCard';
import { PostComposer } from '@/components/PostComposer';
import { EmptyState } from '@/components/EmptyState';
import { LoadingSpinner } from '@/components/LoadingSpinner';
import { InfiniteScroll } from '@/components/InfiniteScroll';

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

interface FeedResponse {
  posts: Post[];
  next_cursor?: string;
}

export default function FeedPage() {
  const { user, isLoading: authLoading } = useAuth();
  const router = useRouter();
  const [posts, setPosts] = useState<Post[]>([]);
  const [cursor, setCursor] = useState<string | undefined>(undefined);
  const [hasMore, setHasMore] = useState(true);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!authLoading && !user) {
      router.replace('/auth/login');
    }
  }, [user, authLoading, router]);

  const loadFeed = useCallback(async (loadCursor?: string) => {
    try {
      setError(null);
      const data: FeedResponse = await api.getFeed({ cursor: loadCursor });
      if (loadCursor) {
        setPosts((prev) => [...prev, ...data.posts]);
      } else {
        setPosts(data.posts);
      }
      setCursor(data.next_cursor);
      setHasMore(!!data.next_cursor);
    } catch (err) {
      setError('Failed to load your feed. Please try again.');
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    if (user) {
      loadFeed();
    }
  }, [user, loadFeed]);

  const loadMore = useCallback(() => {
    if (cursor && hasMore) {
      loadFeed(cursor);
    }
  }, [cursor, hasMore, loadFeed]);

  const handleNewPost = (post: Post) => {
    setPosts((prev) => [post, ...prev]);
  };

  if (authLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <LoadingSpinner />
      </div>
    );
  }

  if (!user) {
    return null;
  }

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      <Nav />
      <main className="mx-auto max-w-2xl px-4 py-6">
        <h1 className="sr-only">Home Feed</h1>

        <div className="mb-6">
          <PostComposer onPost={handleNewPost} />
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
                loadFeed();
              }}
              className="mt-3 text-sm font-medium text-red-600 dark:text-red-400 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600"
            >
              Try again
            </button>
          </div>
        ) : posts.length === 0 ? (
          <EmptyState
            title="Your feed is empty"
            description="Follow people to see their posts here. Head to Discover to find interesting accounts."
            action={{ label: 'Discover people', href: '/discover' }}
          />
        ) : (
          <InfiniteScroll onLoadMore={loadMore} hasMore={hasMore}>
            <div className="space-y-4" role="feed" aria-label="Home feed">
              {posts.map((post) => (
                <PostCard key={post.id} post={post} />
              ))}
            </div>
          </InfiniteScroll>
        )}
      </main>
    </div>
  );
}
