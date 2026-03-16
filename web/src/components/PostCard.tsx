'use client';

import { useState, useCallback, type MouseEvent } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { useRouter } from 'next/navigation';
import {
  Heart,
  MessageCircle,
  Repeat2,
  Share2,
  Bookmark,
  BookmarkCheck,
  MoreHorizontal,
  EyeOff,
  Pencil,
} from 'lucide-react';
import { cn, relativeTime, parseHashtags, formatCount } from '@/lib/utils';
import { Avatar } from '@/components/Avatar';

export interface PostAuthor {
  id: string;
  display_name: string;
  handle: string;
  avatar_url?: string | null;
}

export interface PostMedia {
  id: string;
  url: string;
  type: string;
  alt?: string;
  alt_text?: string;
  width?: number;
  height?: number;
}

export interface PostData {
  id: string;
  author: PostAuthor;
  content: string;
  media?: PostMedia[];
  created_at: string;
  edited_at?: string | null;
  is_nsfw?: boolean;
  visibility?: string;
  like_count: number;
  comment_count?: number;
  reply_count?: number;
  repost_count: number;
  is_liked?: boolean;
  liked?: boolean;
  is_bookmarked?: boolean;
  bookmarked?: boolean;
  reposted?: boolean;
}

export interface PostCardProps {
  post: PostData;
  onLike?: (postId: string) => void;
  onRepost?: (postId: string) => void;
  onShare?: (postId: string) => void;
  onBookmark?: (postId: string) => void;
  className?: string;
}

export function PostCard({ post, onLike, onRepost, onShare, onBookmark, className }: PostCardProps) {
  const router = useRouter();
  const [nsfwRevealed, setNsfwRevealed] = useState(false);
  const [liked, setLiked] = useState(post.is_liked ?? post.liked ?? false);
  const [likeCount, setLikeCount] = useState(post.like_count);
  const [bookmarked, setBookmarked] = useState(post.is_bookmarked ?? post.bookmarked ?? false);

  const navigateToPost = useCallback(() => {
    router.push(`/post/${post.id}`);
  }, [router, post.id]);

  // Prevent card navigation when clicking interactive elements
  const stopProp = (e: MouseEvent) => e.stopPropagation();

  const handleLike = useCallback(
    (e: MouseEvent) => {
      e.stopPropagation();
      setLiked((prev) => !prev);
      setLikeCount((prev) => (liked ? prev - 1 : prev + 1));
      onLike?.(post.id);
    },
    [liked, onLike, post.id],
  );

  const handleBookmark = useCallback(
    (e: MouseEvent) => {
      e.stopPropagation();
      setBookmarked((prev) => !prev);
      onBookmark?.(post.id);
    },
    [onBookmark, post.id],
  );

  const segments = parseHashtags(post.content);
  const showNsfwOverlay = post.is_nsfw && !nsfwRevealed;

  return (
    <article
      onClick={navigateToPost}
      className={cn(
        'cursor-pointer border-b border-gray-100 bg-white px-4 py-4 transition-colors hover:bg-gray-50 dark:border-gray-800 dark:bg-gray-950 dark:hover:bg-gray-900',
        className,
      )}
      role="article"
      aria-label={`Post by ${post.author.display_name}`}
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === 'Enter') navigateToPost();
      }}
    >
      <div className="flex gap-3">
        {/* Avatar */}
        <div onClick={stopProp} className="shrink-0">
          <Avatar
            src={post.author.avatar_url}
            alt={post.author.display_name}
            size="md"
            href={`/profile/${post.author.handle}`}
          />
        </div>

        <div className="min-w-0 flex-1">
          {/* Header */}
          <div className="flex items-center gap-1.5 text-sm">
            <Link
              href={`/profile/${post.author.handle}`}
              className="truncate font-semibold text-gray-900 hover:underline dark:text-gray-100"
              onClick={stopProp}
            >
              {post.author.display_name}
            </Link>
            <Link
              href={`/profile/${post.author.handle}`}
              className="truncate text-gray-500 dark:text-gray-400"
              onClick={stopProp}
            >
              @{post.author.handle}
            </Link>
            <span className="text-gray-300 dark:text-gray-600" aria-hidden="true">·</span>
            <time
              dateTime={post.created_at}
              className="shrink-0 text-gray-500 dark:text-gray-400"
              title={new Date(post.created_at).toLocaleString()}
            >
              {relativeTime(post.created_at)}
            </time>
            {post.edited_at && (
              <span className="flex items-center gap-0.5 text-xs text-gray-400 dark:text-gray-500" title={`Edited ${new Date(post.edited_at).toLocaleString()}`}>
                <Pencil className="h-3 w-3" />
                <span className="sr-only">Edited</span>
              </span>
            )}
          </div>

          {/* Content */}
          <div className="relative mt-1">
            <p className="whitespace-pre-wrap text-sm leading-relaxed text-gray-900 dark:text-gray-100">
              {segments.map((seg, i) =>
                seg.type === 'hashtag' ? (
                  <Link
                    key={i}
                    href={`/discover?tag=${encodeURIComponent(seg.value)}`}
                    className="text-indigo-600 hover:underline dark:text-indigo-400"
                    onClick={stopProp}
                  >
                    #{seg.value}
                  </Link>
                ) : (
                  <span key={i}>{seg.value}</span>
                ),
              )}
            </p>

            {/* NSFW overlay */}
            {showNsfwOverlay && (
              <div className="absolute inset-0 flex flex-col items-center justify-center rounded-lg bg-gray-900/80 backdrop-blur-xl">
                <EyeOff className="mb-2 h-6 w-6 text-gray-300" />
                <p className="text-sm font-medium text-gray-200">Sensitive content</p>
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    setNsfwRevealed(true);
                  }}
                  className="mt-2 rounded-md bg-gray-700 px-3 py-1 text-xs text-gray-200 hover:bg-gray-600"
                >
                  Show anyway
                </button>
              </div>
            )}
          </div>

          {/* Media */}
          {post.media && post.media.length > 0 && (
            <div
              className={cn(
                'relative mt-3 overflow-hidden rounded-xl border border-gray-200 dark:border-gray-700',
                showNsfwOverlay && 'blur-2xl',
              )}
            >
              <MediaGrid media={post.media} />
            </div>
          )}

          {/* Action bar */}
          <div className="mt-3 flex items-center justify-between max-w-md">
            <ActionButton
              icon={<MessageCircle className="h-4 w-4" />}
              count={post.comment_count ?? post.reply_count ?? 0}
              label="Comment"
              onClick={(e) => {
                e.stopPropagation();
                router.push(`/post/${post.id}#comments`);
              }}
            />
            <ActionButton
              icon={<Repeat2 className="h-4 w-4" />}
              count={post.repost_count}
              label="Repost"
              onClick={(e) => {
                e.stopPropagation();
                onRepost?.(post.id);
              }}
            />
            <ActionButton
              icon={<Heart className={cn('h-4 w-4', liked && 'fill-red-500 text-red-500')} />}
              count={likeCount}
              label={liked ? 'Unlike' : 'Like'}
              active={liked}
              activeColor="text-red-500"
              onClick={handleLike}
            />
            <ActionButton
              icon={<Share2 className="h-4 w-4" />}
              label="Share"
              onClick={(e) => {
                e.stopPropagation();
                onShare?.(post.id);
              }}
            />
            <ActionButton
              icon={
                bookmarked ? (
                  <BookmarkCheck className="h-4 w-4 fill-indigo-500 text-indigo-500" />
                ) : (
                  <Bookmark className="h-4 w-4" />
                )
              }
              label={bookmarked ? 'Remove bookmark' : 'Bookmark'}
              active={bookmarked}
              activeColor="text-indigo-500"
              onClick={handleBookmark}
            />
          </div>
        </div>
      </div>
    </article>
  );
}

/* ------------------------------------------------------------------ */
/*  Internal sub-components                                            */
/* ------------------------------------------------------------------ */

interface ActionButtonProps {
  icon: React.ReactNode;
  count?: number;
  label: string;
  active?: boolean;
  activeColor?: string;
  onClick: (e: MouseEvent<HTMLButtonElement>) => void;
}

function ActionButton({ icon, count, label, active, activeColor, onClick }: ActionButtonProps) {
  return (
    <button
      onClick={onClick}
      className={cn(
        'group flex items-center gap-1 rounded-full p-1.5 text-gray-500 transition-colors hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-800',
        active && activeColor,
      )}
      aria-label={label}
    >
      {icon}
      {count !== undefined && count > 0 && (
        <span className="text-xs">{formatCount(count)}</span>
      )}
    </button>
  );
}

function MediaGrid({ media }: { media: PostMedia[] }) {
  if (media.length === 1) {
    const m = media[0];
    if (m.type === 'video') {
      return (
        <video
          src={m.url}
          controls
          className="max-h-96 w-full object-contain bg-black"
          aria-label={m.alt ?? 'Video'}
        />
      );
    }
    return (
      <Image
        src={m.url}
        alt={m.alt ?? ''}
        width={m.width ?? 600}
        height={m.height ?? 400}
        className="max-h-96 w-full object-cover"
      />
    );
  }

  return (
    <div
      className={cn(
        'grid gap-0.5',
        media.length === 2 && 'grid-cols-2',
        media.length === 3 && 'grid-cols-2',
        media.length >= 4 && 'grid-cols-2',
      )}
    >
      {media.slice(0, 4).map((m, i) => (
        <div
          key={m.id}
          className={cn(
            'relative overflow-hidden',
            media.length === 3 && i === 0 && 'row-span-2',
          )}
        >
          {m.type === 'video' ? (
            <video
              src={m.url}
              controls
              className="h-48 w-full object-cover bg-black"
              aria-label={m.alt ?? 'Video'}
            />
          ) : (
            <Image
              src={m.url}
              alt={m.alt ?? ''}
              width={m.width ?? 400}
              height={m.height ?? 300}
              className="h-48 w-full object-cover"
            />
          )}
          {i === 3 && media.length > 4 && (
            <div className="absolute inset-0 flex items-center justify-center bg-black/50 text-xl font-bold text-white">
              +{media.length - 4}
            </div>
          )}
        </div>
      ))}
    </div>
  );
}
