'use client';

import { useEffect, useRef, useCallback, type ReactNode } from 'react';
import { cn } from '@/lib/utils';
import { LoadingSpinner } from '@/components/LoadingSpinner';

export interface InfiniteScrollProps {
  children: ReactNode;
  onLoadMore: () => void;
  loading?: boolean;
  hasMore?: boolean;
  /** Distance in pixels from the bottom to trigger load (default 300) */
  threshold?: number;
  endMessage?: string;
  className?: string;
}

export function InfiniteScroll({
  children,
  onLoadMore,
  loading = false,
  hasMore = true,
  threshold = 300,
  endMessage = 'You\u2019ve reached the end.',
  className,
}: InfiniteScrollProps) {
  const sentinelRef = useRef<HTMLDivElement>(null);
  const loadMoreRef = useRef(onLoadMore);

  // Keep the callback ref fresh without re-creating the observer
  useEffect(() => {
    loadMoreRef.current = onLoadMore;
  }, [onLoadMore]);

  useEffect(() => {
    const sentinel = sentinelRef.current;
    if (!sentinel || !hasMore || loading) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0]?.isIntersecting) {
          loadMoreRef.current();
        }
      },
      { rootMargin: `0px 0px ${threshold}px 0px` },
    );

    observer.observe(sentinel);

    return () => {
      observer.disconnect();
    };
  }, [hasMore, loading, threshold]);

  return (
    <div className={cn(className)} role="feed" aria-busy={loading}>
      {children}

      {/* Sentinel element */}
      <div ref={sentinelRef} aria-hidden="true" />

      {/* Loading indicator */}
      {loading && (
        <div className="flex justify-center py-6" role="status" aria-label="Loading more content">
          <LoadingSpinner size="md" />
        </div>
      )}

      {/* End message */}
      {!hasMore && !loading && (
        <p className="py-8 text-center text-sm text-gray-400 dark:text-gray-500">
          {endMessage}
        </p>
      )}
    </div>
  );
}
