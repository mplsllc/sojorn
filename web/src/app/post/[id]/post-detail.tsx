'use client';

import { useState, FormEvent } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { api } from '@/lib/api';
import { useAuth } from '@/lib/auth';
import { PostCard } from '@/components/PostCard';
import { LoadingSpinner } from '@/components/LoadingSpinner';
import { Button } from '@/components/Button';
import {
  Heart,
  MessageCircle,
  Repeat2,
  Bookmark,
  Share,
  Clock,
  ArrowLeft,
} from 'lucide-react';

interface PostAuthor {
  id: string;
  handle: string;
  display_name: string;
  avatar_url: string;
}

interface PostMedia {
  id: string;
  url: string;
  type: string;
  alt_text?: string;
  preview_url?: string;
}

interface Post {
  id: string;
  content: string;
  content_html: string;
  author: PostAuthor;
  media: PostMedia[];
  like_count: number;
  reply_count: number;
  repost_count: number;
  liked: boolean;
  reposted: boolean;
  bookmarked: boolean;
  created_at: string;
  edited_at?: string;
  visibility: string;
  parent_id?: string;
  replies: Post[];
}

function formatDate(dateStr: string): string {
  const date = new Date(dateStr);
  return date.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

export default function PostDetail({ post }: { post: Post }) {
  const { user } = useAuth();
  const router = useRouter();
  const [liked, setLiked] = useState(post.liked);
  const [likeCount, setLikeCount] = useState(post.like_count);
  const [reposted, setReposted] = useState(post.reposted);
  const [repostCount, setRepostCount] = useState(post.repost_count);
  const [bookmarked, setBookmarked] = useState(post.bookmarked);
  const [replyContent, setReplyContent] = useState('');
  const [isReplying, setIsReplying] = useState(false);
  const [replies, setReplies] = useState<Post[]>(post.replies || []);

  const handleLike = async () => {
    if (!user) return;
    const wasLiked = liked;
    setLiked(!liked);
    setLikeCount((c) => (wasLiked ? c - 1 : c + 1));
    try {
      if (wasLiked) {
        await api.unlikePost(post.id);
      } else {
        await api.likePost(post.id);
      }
    } catch {
      setLiked(wasLiked);
      setLikeCount((c) => (wasLiked ? c + 1 : c - 1));
    }
  };

  const handleRepost = async () => {
    if (!user) return;
    const wasReposted = reposted;
    setReposted(!reposted);
    setRepostCount((c) => (wasReposted ? c - 1 : c + 1));
    try {
      if (wasReposted) {
        await api.unrepost(post.id);
      } else {
        await api.repost(post.id);
      }
    } catch {
      setReposted(wasReposted);
      setRepostCount((c) => (wasReposted ? c + 1 : c - 1));
    }
  };

  const handleBookmark = async () => {
    if (!user) return;
    const wasBookmarked = bookmarked;
    setBookmarked(!bookmarked);
    try {
      if (wasBookmarked) {
        await api.unbookmark(post.id);
      } else {
        await api.bookmark(post.id);
      }
    } catch {
      setBookmarked(wasBookmarked);
    }
  };

  const handleReply = async (e: FormEvent) => {
    e.preventDefault();
    if (!replyContent.trim() || !user) return;
    setIsReplying(true);
    try {
      const newReply = await api.createPost({
        content: replyContent,
        parent_id: post.id,
      });
      setReplies((prev) => [newReply, ...prev]);
      setReplyContent('');
    } catch {
      // Keep content on error so user doesn't lose it
    } finally {
      setIsReplying(false);
    }
  };

  const handleShare = async () => {
    const url = `${window.location.origin}/post/${post.id}`;
    if (navigator.share) {
      try {
        await navigator.share({ url });
      } catch {
        // User cancelled
      }
    } else {
      await navigator.clipboard.writeText(url);
    }
  };

  return (
    <main className="mx-auto max-w-2xl px-4 py-6">
      {/* Back button */}
      <button
        onClick={() => router.back()}
        className="mb-4 inline-flex items-center gap-1.5 text-sm text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600"
        aria-label="Go back"
      >
        <ArrowLeft className="h-4 w-4" aria-hidden="true" />
        Back
      </button>

      <article
        className="rounded-xl border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-4 sm:p-6"
        aria-label={`Post by @${post.author.handle}`}
      >
        {/* Author */}
        <div className="flex items-center gap-3">
          <Link
            href={`/profile/${post.author.handle}`}
            className="relative h-12 w-12 rounded-full overflow-hidden bg-gray-200 dark:bg-gray-800 flex-shrink-0"
          >
            {post.author.avatar_url ? (
              <Image
                src={post.author.avatar_url}
                alt={`${post.author.display_name || post.author.handle}'s avatar`}
                fill
                className="object-cover"
              />
            ) : (
              <span className="flex h-full w-full items-center justify-center text-lg font-bold text-gray-400">
                {(post.author.display_name || post.author.handle)[0]?.toUpperCase()}
              </span>
            )}
          </Link>
          <div>
            <Link
              href={`/profile/${post.author.handle}`}
              className="font-semibold text-gray-900 dark:text-gray-50 hover:underline"
            >
              {post.author.display_name || post.author.handle}
            </Link>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              @{post.author.handle}
            </p>
          </div>
        </div>

        {/* Content */}
        <div
          className="mt-4 text-gray-900 dark:text-gray-100 text-lg leading-relaxed whitespace-pre-line break-words"
          dangerouslySetInnerHTML={{ __html: post.content_html || post.content }}
        />

        {/* Media */}
        {post.media.length > 0 && (
          <div
            className={`mt-4 grid gap-2 ${
              post.media.length === 1
                ? 'grid-cols-1'
                : post.media.length === 2
                  ? 'grid-cols-2'
                  : 'grid-cols-2'
            }`}
          >
            {post.media.map((media) => (
              <div
                key={media.id}
                className="relative rounded-xl overflow-hidden bg-gray-100 dark:bg-gray-800"
              >
                {media.type === 'image' ? (
                  <Image
                    src={media.url}
                    alt={media.alt_text || 'Post image'}
                    width={600}
                    height={400}
                    className="w-full h-auto object-cover"
                  />
                ) : media.type === 'video' ? (
                  <video
                    src={media.url}
                    controls
                    className="w-full h-auto"
                    poster={media.preview_url}
                    aria-label={media.alt_text || 'Post video'}
                  />
                ) : null}
              </div>
            ))}
          </div>
        )}

        {/* Timestamp & edit history */}
        <div className="mt-4 flex items-center gap-3 text-sm text-gray-500 dark:text-gray-400">
          <time dateTime={post.created_at}>{formatDate(post.created_at)}</time>
          {post.edited_at && (
            <Link
              href={`/post/${post.id}/history`}
              className="inline-flex items-center gap-1 hover:text-gray-700 dark:hover:text-gray-300 transition-colors"
            >
              <Clock className="h-3.5 w-3.5" aria-hidden="true" />
              Edited
            </Link>
          )}
        </div>

        {/* Stats */}
        {(likeCount > 0 || repostCount > 0 || post.reply_count > 0) && (
          <div className="mt-3 flex items-center gap-4 border-t border-gray-100 dark:border-gray-800 pt-3 text-sm">
            {repostCount > 0 && (
              <span>
                <span className="font-semibold text-gray-900 dark:text-gray-100">
                  {repostCount.toLocaleString()}
                </span>{' '}
                <span className="text-gray-500 dark:text-gray-400">
                  {repostCount === 1 ? 'Repost' : 'Reposts'}
                </span>
              </span>
            )}
            {likeCount > 0 && (
              <span>
                <span className="font-semibold text-gray-900 dark:text-gray-100">
                  {likeCount.toLocaleString()}
                </span>{' '}
                <span className="text-gray-500 dark:text-gray-400">
                  {likeCount === 1 ? 'Like' : 'Likes'}
                </span>
              </span>
            )}
            {post.reply_count > 0 && (
              <span>
                <span className="font-semibold text-gray-900 dark:text-gray-100">
                  {post.reply_count.toLocaleString()}
                </span>{' '}
                <span className="text-gray-500 dark:text-gray-400">
                  {post.reply_count === 1 ? 'Reply' : 'Replies'}
                </span>
              </span>
            )}
          </div>
        )}

        {/* Actions */}
        <div className="mt-3 flex items-center justify-between border-t border-gray-100 dark:border-gray-800 pt-3">
          <button
            onClick={handleLike}
            className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 ${
              liked
                ? 'text-red-500 hover:text-red-600'
                : 'text-gray-500 dark:text-gray-400 hover:text-red-500'
            }`}
            aria-label={liked ? 'Unlike this post' : 'Like this post'}
            aria-pressed={liked}
          >
            <Heart
              className={`h-5 w-5 ${liked ? 'fill-current' : ''}`}
              aria-hidden="true"
            />
          </button>

          <button
            onClick={handleRepost}
            className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 ${
              reposted
                ? 'text-green-500 hover:text-green-600'
                : 'text-gray-500 dark:text-gray-400 hover:text-green-500'
            }`}
            aria-label={reposted ? 'Undo repost' : 'Repost'}
            aria-pressed={reposted}
          >
            <Repeat2 className="h-5 w-5" aria-hidden="true" />
          </button>

          <button
            onClick={handleBookmark}
            className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 ${
              bookmarked
                ? 'text-brand-500 hover:text-brand-600'
                : 'text-gray-500 dark:text-gray-400 hover:text-brand-500'
            }`}
            aria-label={bookmarked ? 'Remove bookmark' : 'Bookmark this post'}
            aria-pressed={bookmarked}
          >
            <Bookmark
              className={`h-5 w-5 ${bookmarked ? 'fill-current' : ''}`}
              aria-hidden="true"
            />
          </button>

          <button
            onClick={handleShare}
            className="inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm text-gray-500 dark:text-gray-400 hover:text-brand-500 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600"
            aria-label="Share this post"
          >
            <Share className="h-5 w-5" aria-hidden="true" />
          </button>
        </div>
      </article>

      {/* Reply form */}
      {user && (
        <form
          onSubmit={handleReply}
          className="mt-4 rounded-xl border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-4"
        >
          <label htmlFor="reply-content" className="sr-only">
            Write a reply
          </label>
          <textarea
            id="reply-content"
            value={replyContent}
            onChange={(e) => setReplyContent(e.target.value)}
            placeholder="Write a reply..."
            rows={3}
            className="block w-full resize-none border-0 bg-transparent text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:ring-0 focus:outline-none"
            aria-label="Reply to this post"
          />
          <div className="mt-3 flex justify-end">
            <Button
              type="submit"
              disabled={!replyContent.trim() || isReplying}
              variant="primary"
            >
              {isReplying ? (
                <span className="inline-flex items-center gap-2">
                  <LoadingSpinner />
                  Replying...
                </span>
              ) : (
                'Reply'
              )}
            </Button>
          </div>
        </form>
      )}

      {/* Replies */}
      {replies.length > 0 && (
        <section className="mt-4 space-y-4" aria-label="Replies">
          <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
            Replies
          </h2>
          {replies.map((reply) => (
            <PostCard key={reply.id} post={reply} />
          ))}
        </section>
      )}

      {!user && (
        <div className="mt-4 rounded-xl border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-6 text-center">
          <p className="text-sm text-gray-600 dark:text-gray-400">
            <Link
              href="/auth/login"
              className="font-medium text-brand-600 dark:text-brand-400 hover:underline"
            >
              Sign in
            </Link>{' '}
            to join the conversation.
          </p>
        </div>
      )}
    </main>
  );
}
