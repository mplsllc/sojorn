'use client';

import { useState, useCallback, useRef, type FormEvent } from 'react';
import Link from 'next/link';
import { CornerDownRight, Send } from 'lucide-react';
import { cn, relativeTime } from '@/lib/utils';
import { Avatar } from '@/components/Avatar';
import { Button } from '@/components/Button';
import { EmptyState } from '@/components/EmptyState';

export interface CommentAuthor {
  id: string;
  display_name: string;
  handle: string;
  avatar_url?: string | null;
}

export interface CommentData {
  id: string;
  author: CommentAuthor;
  content: string;
  created_at: string;
  parent_id?: string | null;
  replies?: CommentData[];
}

export interface CommentSectionProps {
  comments: CommentData[];
  /** Currently authenticated user — needed for the input */
  currentUser?: {
    display_name: string;
    avatar_url?: string | null;
  } | null;
  onSubmit?: (content: string, parentId?: string) => void;
  loading?: boolean;
  className?: string;
}

export function CommentSection({
  comments,
  currentUser,
  onSubmit,
  loading,
  className,
}: CommentSectionProps) {
  return (
    <section
      id="comments"
      className={cn('divide-y divide-gray-100 dark:divide-gray-800', className)}
      aria-label="Comments"
    >
      {comments.length === 0 && !loading && (
        <EmptyState
          title="No comments yet"
          description="Be the first to share your thoughts."
          className="py-8"
        />
      )}

      {comments.map((comment) => (
        <CommentThread key={comment.id} comment={comment} depth={0} onReply={onSubmit} />
      ))}

      {/* Comment input */}
      {currentUser && (
        <CommentInput
          avatar={currentUser.avatar_url}
          displayName={currentUser.display_name}
          onSubmit={(content) => onSubmit?.(content)}
          placeholder="Write a comment..."
        />
      )}
    </section>
  );
}

/* ------------------------------------------------------------------ */
/*  Comment thread (recursive)                                         */
/* ------------------------------------------------------------------ */

const MAX_DEPTH = 4;

interface CommentThreadProps {
  comment: CommentData;
  depth: number;
  onReply?: (content: string, parentId?: string) => void;
}

function CommentThread({ comment, depth, onReply }: CommentThreadProps) {
  const [showReplyInput, setShowReplyInput] = useState(false);

  const handleReply = useCallback(
    (content: string) => {
      onReply?.(content, comment.id);
      setShowReplyInput(false);
    },
    [onReply, comment.id],
  );

  return (
    <div className={cn(depth > 0 && 'border-l-2 border-gray-100 dark:border-gray-800')}>
      <div className={cn('flex gap-3 px-4 py-3', depth > 0 && 'pl-4')}>
        <Avatar
          src={comment.author.avatar_url}
          alt={comment.author.display_name}
          size="sm"
          href={`/profile/${comment.author.handle}`}
        />
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-1.5 text-sm">
            <Link
              href={`/profile/${comment.author.handle}`}
              className="font-semibold text-gray-900 hover:underline dark:text-gray-100"
            >
              {comment.author.display_name}
            </Link>
            <span className="text-gray-500 dark:text-gray-400">@{comment.author.handle}</span>
            <span className="text-gray-300 dark:text-gray-600" aria-hidden>·</span>
            <time
              dateTime={comment.created_at}
              className="text-gray-500 dark:text-gray-400"
              title={new Date(comment.created_at).toLocaleString()}
            >
              {relativeTime(comment.created_at)}
            </time>
          </div>

          <p className="mt-0.5 whitespace-pre-wrap text-sm leading-relaxed text-gray-800 dark:text-gray-200">
            {comment.content}
          </p>

          {depth < MAX_DEPTH && (
            <button
              onClick={() => setShowReplyInput((v) => !v)}
              className="mt-1 flex items-center gap-1 text-xs font-medium text-gray-500 hover:text-indigo-600 dark:text-gray-400 dark:hover:text-indigo-400"
              aria-label={`Reply to ${comment.author.display_name}`}
            >
              <CornerDownRight className="h-3 w-3" />
              Reply
            </button>
          )}

          {showReplyInput && (
            <div className="mt-2">
              <CommentInput
                onSubmit={handleReply}
                placeholder={`Reply to @${comment.author.handle}...`}
                compact
              />
            </div>
          )}
        </div>
      </div>

      {/* Nested replies */}
      {comment.replies && comment.replies.length > 0 && (
        <div className="ml-6">
          {comment.replies.map((reply) => (
            <CommentThread
              key={reply.id}
              comment={reply}
              depth={depth + 1}
              onReply={onReply}
            />
          ))}
        </div>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Comment input                                                      */
/* ------------------------------------------------------------------ */

interface CommentInputProps {
  avatar?: string | null;
  displayName?: string;
  onSubmit: (content: string) => void;
  placeholder?: string;
  compact?: boolean;
}

function CommentInput({ avatar, displayName, onSubmit, placeholder, compact }: CommentInputProps) {
  const [value, setValue] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  const handleSubmit = useCallback(
    async (e: FormEvent) => {
      e.preventDefault();
      const trimmed = value.trim();
      if (!trimmed) return;
      setSubmitting(true);
      try {
        onSubmit(trimmed);
        setValue('');
      } finally {
        setSubmitting(false);
      }
    },
    [value, onSubmit],
  );

  return (
    <form
      onSubmit={handleSubmit}
      className={cn('flex items-start gap-3 px-4 py-3', !compact && 'border-t border-gray-100 dark:border-gray-800')}
    >
      {avatar !== undefined && displayName && (
        <Avatar src={avatar} alt={displayName} size="sm" />
      )}
      <div className="flex min-w-0 flex-1 items-end gap-2">
        <textarea
          ref={inputRef}
          value={value}
          onChange={(e) => setValue(e.target.value)}
          placeholder={placeholder ?? 'Write a comment...'}
          rows={1}
          className="min-h-[36px] flex-1 resize-none rounded-lg border border-gray-200 bg-gray-50 px-3 py-2 text-sm text-gray-900 placeholder:text-gray-400 focus:border-indigo-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/30 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-100 dark:placeholder:text-gray-500"
          aria-label={placeholder ?? 'Write a comment'}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault();
              handleSubmit(e);
            }
          }}
        />
        <Button
          type="submit"
          size="sm"
          variant="primary"
          disabled={!value.trim()}
          loading={submitting}
          aria-label="Submit comment"
        >
          <Send className="h-4 w-4" />
        </Button>
      </div>
    </form>
  );
}
