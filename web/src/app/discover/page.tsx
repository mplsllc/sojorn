'use client';

import { useState, useEffect, useCallback, FormEvent, Suspense } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { api } from '@/lib/api';
import { Nav } from '@/components/Nav';
import { PostCard } from '@/components/PostCard';
import { ProfileCard } from '@/components/ProfileCard';
import { LoadingSpinner } from '@/components/LoadingSpinner';
import { EmptyState } from '@/components/EmptyState';
import { InfiniteScroll } from '@/components/InfiniteScroll';
import { Search, TrendingUp, Hash, X } from 'lucide-react';

interface Post {
  id: string;
  content: string;
  author: {
    id: string;
    handle: string;
    display_name: string;
    avatar_url: string;
  };
  media: Array<{ id: string; url: string; type: string; alt_text?: string }>;
  like_count: number;
  reply_count: number;
  repost_count: number;
  liked: boolean;
  reposted: boolean;
  bookmarked: boolean;
  created_at: string;
  visibility: string;
}

interface UserProfile {
  id: string;
  handle: string;
  display_name: string;
  bio: string;
  avatar_url: string;
  follower_count: number;
  following_count: number;
  is_following?: boolean;
}

interface Hashtag {
  name: string;
  url: string;
  post_count: number;
  trending: boolean;
}

interface DiscoverData {
  trending_hashtags: Hashtag[];
  suggested_users: UserProfile[];
  trending_posts: Post[];
}

interface SearchResult {
  posts: Post[];
  users: UserProfile[];
  hashtags: Hashtag[];
  next_cursor?: string;
}

type SearchTab = 'all' | 'posts' | 'people' | 'hashtags';

const searchTabs: { key: SearchTab; label: string }[] = [
  { key: 'all', label: 'All' },
  { key: 'posts', label: 'Posts' },
  { key: 'people', label: 'People' },
  { key: 'hashtags', label: 'Hashtags' },
];

export default function DiscoverPage() {
  return (
    <Suspense>
      <DiscoverContent />
    </Suspense>
  );
}

function DiscoverContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const initialQuery = searchParams.get('q') || '';

  const [query, setQuery] = useState(initialQuery);
  const [activeQuery, setActiveQuery] = useState(initialQuery);
  const [activeTab, setActiveTab] = useState<SearchTab>('all');
  const [discover, setDiscover] = useState<DiscoverData | null>(null);
  const [results, setResults] = useState<SearchResult | null>(null);
  const [cursor, setCursor] = useState<string | undefined>(undefined);
  const [hasMore, setHasMore] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [isSearching, setIsSearching] = useState(false);

  useEffect(() => {
    if (!initialQuery) {
      api
        .getDiscover()
        .then((data: DiscoverData) => {
          setDiscover(data);
        })
        .catch(() => {})
        .finally(() => setIsLoading(false));
    } else {
      performSearch(initialQuery, 'all');
    }
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const performSearch = async (
    searchQuery: string,
    tab: SearchTab,
    searchCursor?: string
  ) => {
    if (!searchQuery.trim()) return;
    setIsSearching(true);

    try {
      const data: SearchResult = await api.search(searchQuery, {
        type: tab === 'all' ? undefined : tab,
        cursor: searchCursor,
      });

      if (searchCursor) {
        setResults((prev) =>
          prev
            ? {
                posts: [...prev.posts, ...data.posts],
                users: [...prev.users, ...data.users],
                hashtags: [...prev.hashtags, ...data.hashtags],
                next_cursor: data.next_cursor,
              }
            : data
        );
      } else {
        setResults(data);
      }
      setCursor(data.next_cursor);
      setHasMore(!!data.next_cursor);
    } catch {
      // Keep existing results on error
    } finally {
      setIsSearching(false);
      setIsLoading(false);
    }
  };

  const handleSearch = (e: FormEvent) => {
    e.preventDefault();
    if (!query.trim()) return;
    setActiveQuery(query);
    setActiveTab('all');
    setResults(null);
    setCursor(undefined);
    router.replace(`/discover?q=${encodeURIComponent(query)}`);
    performSearch(query, 'all');
  };

  const clearSearch = () => {
    setQuery('');
    setActiveQuery('');
    setResults(null);
    setCursor(undefined);
    setHasMore(false);
    router.replace('/discover');
    if (!discover) {
      setIsLoading(true);
      api
        .getDiscover()
        .then((data: DiscoverData) => setDiscover(data))
        .catch(() => {})
        .finally(() => setIsLoading(false));
    }
  };

  const switchTab = (tab: SearchTab) => {
    setActiveTab(tab);
    setResults(null);
    setCursor(undefined);
    performSearch(activeQuery, tab);
  };

  const loadMore = useCallback(() => {
    if (cursor && hasMore && activeQuery) {
      performSearch(activeQuery, activeTab, cursor);
    }
  }, [cursor, hasMore, activeQuery, activeTab]); // eslint-disable-line react-hooks/exhaustive-deps

  const handleHashtagClick = (tag: string) => {
    const q = `#${tag}`;
    setQuery(q);
    setActiveQuery(q);
    setActiveTab('all');
    setResults(null);
    router.replace(`/discover?q=${encodeURIComponent(q)}`);
    performSearch(q, 'all');
  };

  const isSearchMode = activeQuery.length > 0;

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      <Nav />
      <main className="mx-auto max-w-2xl px-4 py-6">
        <h1 className="sr-only">Discover</h1>

        {/* Search bar */}
        <form onSubmit={handleSearch} className="relative mb-6" role="search">
          <label htmlFor="discover-search" className="sr-only">
            Search posts, people, and hashtags
          </label>
          <Search
            className="absolute left-3.5 top-1/2 -translate-y-1/2 h-5 w-5 text-gray-400"
            aria-hidden="true"
          />
          <input
            id="discover-search"
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search posts, people, and hashtags..."
            className="block w-full rounded-xl border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 pl-11 pr-10 py-3 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 focus:outline-none transition-colors"
          />
          {query && (
            <button
              type="button"
              onClick={clearSearch}
              className="absolute right-3.5 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
              aria-label="Clear search"
            >
              <X className="h-5 w-5" />
            </button>
          )}
        </form>

        {isLoading ? (
          <div className="flex justify-center py-12">
            <LoadingSpinner />
          </div>
        ) : isSearchMode ? (
          <>
            {/* Search tabs */}
            <div
              className="mb-6 border-b border-gray-200 dark:border-gray-800"
              role="tablist"
              aria-label="Search result tabs"
            >
              <div className="flex">
                {searchTabs.map((tab) => (
                  <button
                    key={tab.key}
                    role="tab"
                    aria-selected={activeTab === tab.key}
                    onClick={() => switchTab(tab.key)}
                    className={`flex-1 px-4 py-2.5 text-sm font-medium text-center border-b-2 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-brand-600 ${
                      activeTab === tab.key
                        ? 'border-brand-600 text-brand-600 dark:border-brand-400 dark:text-brand-400'
                        : 'border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
                    }`}
                  >
                    {tab.label}
                  </button>
                ))}
              </div>
            </div>

            {isSearching && !results ? (
              <div className="flex justify-center py-12">
                <LoadingSpinner />
              </div>
            ) : results &&
              results.posts.length === 0 &&
              results.users.length === 0 &&
              results.hashtags.length === 0 ? (
              <EmptyState
                title="No results found"
                description={`No results for "${activeQuery}". Try a different search term.`}
              />
            ) : (
              <InfiniteScroll onLoadMore={loadMore} hasMore={hasMore}>
                <div className="space-y-6">
                  {/* Users */}
                  {(activeTab === 'all' || activeTab === 'people') &&
                    results &&
                    results.users.length > 0 && (
                      <section aria-label="People results">
                        {activeTab === 'all' && (
                          <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100 mb-3">
                            People
                          </h2>
                        )}
                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                          {results.users.map((user) => (
                            <ProfileCard key={user.id} user={user} />
                          ))}
                        </div>
                      </section>
                    )}

                  {/* Hashtags */}
                  {(activeTab === 'all' || activeTab === 'hashtags') &&
                    results &&
                    results.hashtags.length > 0 && (
                      <section aria-label="Hashtag results">
                        {activeTab === 'all' && (
                          <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100 mb-3">
                            Hashtags
                          </h2>
                        )}
                        <div className="space-y-2">
                          {results.hashtags.map((tag) => (
                            <button
                              key={tag.name}
                              onClick={() => handleHashtagClick(tag.name)}
                              className="flex w-full items-center justify-between rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-3 text-left hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600"
                            >
                              <div className="flex items-center gap-2">
                                <Hash
                                  className="h-4 w-4 text-brand-500"
                                  aria-hidden="true"
                                />
                                <span className="font-medium text-gray-900 dark:text-gray-100">
                                  {tag.name}
                                </span>
                              </div>
                              <span className="text-sm text-gray-500 dark:text-gray-400">
                                {tag.post_count.toLocaleString()} posts
                              </span>
                            </button>
                          ))}
                        </div>
                      </section>
                    )}

                  {/* Posts */}
                  {(activeTab === 'all' || activeTab === 'posts') &&
                    results &&
                    results.posts.length > 0 && (
                      <section aria-label="Post results">
                        {activeTab === 'all' && (
                          <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100 mb-3">
                            Posts
                          </h2>
                        )}
                        <div
                          className="space-y-4"
                          role="feed"
                          aria-label="Search results"
                        >
                          {results.posts.map((post) => (
                            <PostCard key={post.id} post={post} />
                          ))}
                        </div>
                      </section>
                    )}
                </div>
              </InfiniteScroll>
            )}
          </>
        ) : (
          /* Discover mode */
          <div className="space-y-8">
            {/* Trending hashtags */}
            {discover?.trending_hashtags &&
              discover.trending_hashtags.length > 0 && (
                <section aria-label="Trending hashtags">
                  <div className="flex items-center gap-2 mb-4">
                    <TrendingUp
                      className="h-5 w-5 text-brand-500"
                      aria-hidden="true"
                    />
                    <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-50">
                      Trending
                    </h2>
                  </div>
                  <div className="space-y-2">
                    {discover.trending_hashtags.map((tag) => (
                      <button
                        key={tag.name}
                        onClick={() => handleHashtagClick(tag.name)}
                        className="flex w-full items-center justify-between rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-3 text-left hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600"
                      >
                        <div>
                          <p className="font-medium text-gray-900 dark:text-gray-100">
                            #{tag.name}
                          </p>
                          <p className="text-sm text-gray-500 dark:text-gray-400">
                            {tag.post_count.toLocaleString()} posts
                          </p>
                        </div>
                      </button>
                    ))}
                  </div>
                </section>
              )}

            {/* Suggested users */}
            {discover?.suggested_users &&
              discover.suggested_users.length > 0 && (
                <section aria-label="Suggested users">
                  <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-50 mb-4">
                    Suggested for you
                  </h2>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    {discover.suggested_users.map((user) => (
                      <ProfileCard key={user.id} user={user} />
                    ))}
                  </div>
                </section>
              )}

            {/* Trending posts */}
            {discover?.trending_posts &&
              discover.trending_posts.length > 0 && (
                <section aria-label="Trending posts">
                  <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-50 mb-4">
                    Popular posts
                  </h2>
                  <div
                    className="space-y-4"
                    role="feed"
                    aria-label="Trending posts"
                  >
                    {discover.trending_posts.map((post) => (
                      <PostCard key={post.id} post={post} />
                    ))}
                  </div>
                </section>
              )}

            {!discover?.trending_hashtags?.length &&
              !discover?.suggested_users?.length &&
              !discover?.trending_posts?.length && (
                <EmptyState
                  title="Nothing to discover yet"
                  description="Check back later for trending content and suggested accounts."
                />
              )}
          </div>
        )}
      </main>
    </div>
  );
}
