'use client';

import { useState, useCallback, useRef, type FormEvent, type ChangeEvent } from 'react';
import {
  ImagePlus,
  Video,
  Globe,
  Users,
  ChevronDown,
  X,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { Avatar } from '@/components/Avatar';
import { Button } from '@/components/Button';

export type PostVisibility = 'public' | 'followers';

export interface PostComposerProps {
  user?: {
    display_name: string;
    avatar_url?: string | null;
  };
  maxLength?: number;
  onSubmit?: (data: {
    content: string;
    visibility: PostVisibility;
    mediaFiles: File[];
  }) => void | Promise<void>;
  onPost?: (post: any) => void;
  /** Start expanded */
  defaultExpanded?: boolean;
  className?: string;
}

export function PostComposer({
  user,
  maxLength = 5000,
  onSubmit,
  defaultExpanded = false,
  className,
}: PostComposerProps) {
  const [expanded, setExpanded] = useState(defaultExpanded);
  const [content, setContent] = useState('');
  const [visibility, setVisibility] = useState<PostVisibility>('public');
  const [visMenuOpen, setVisMenuOpen] = useState(false);
  const [mediaFiles, setMediaFiles] = useState<File[]>([]);
  const [mediaPreviews, setMediaPreviews] = useState<string[]>([]);
  const [submitting, setSubmitting] = useState(false);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const charsLeft = maxLength - content.length;
  const overLimit = charsLeft < 0;
  const canSubmit = content.trim().length > 0 && !overLimit && !submitting;

  const expand = useCallback(() => {
    setExpanded(true);
    requestAnimationFrame(() => textareaRef.current?.focus());
  }, []);

  const addMedia = useCallback((e: ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files ?? []);
    if (!files.length) return;

    setMediaFiles((prev) => [...prev, ...files]);
    const urls = files.map((f) => URL.createObjectURL(f));
    setMediaPreviews((prev) => [...prev, ...urls]);

    // Reset the input so the same file can be re-selected
    e.target.value = '';
  }, []);

  const removeMedia = useCallback((index: number) => {
    setMediaPreviews((prev) => {
      URL.revokeObjectURL(prev[index]);
      return prev.filter((_, i) => i !== index);
    });
    setMediaFiles((prev) => prev.filter((_, i) => i !== index));
  }, []);

  const handleSubmit = useCallback(
    async (e: FormEvent) => {
      e.preventDefault();
      if (!canSubmit) return;
      setSubmitting(true);
      try {
        await onSubmit?.({ content: content.trim(), visibility, mediaFiles });
        setContent('');
        setMediaFiles([]);
        setMediaPreviews((prev) => {
          prev.forEach((u) => URL.revokeObjectURL(u));
          return [];
        });
        setExpanded(false);
      } finally {
        setSubmitting(false);
      }
    },
    [canSubmit, content, visibility, mediaFiles, onSubmit],
  );

  // Auto-resize textarea
  const handleInput = useCallback(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${el.scrollHeight}px`;
  }, []);

  return (
    <div
      className={cn(
        'rounded-xl border border-gray-200 bg-white p-4 dark:border-gray-800 dark:bg-gray-950',
        className,
      )}
    >
      {!expanded ? (
        /* Collapsed state */
        <button
          onClick={expand}
          className="flex w-full items-center gap-3 text-left"
          aria-label="Create a new post"
        >
          <Avatar src={user?.avatar_url} alt={user?.display_name ?? ''} size="md" />
          <span className="flex-1 text-sm text-gray-400 dark:text-gray-500">
            What&apos;s happening?
          </span>
        </button>
      ) : (
        /* Expanded state */
        <form onSubmit={handleSubmit}>
          <div className="flex gap-3">
            <Avatar src={user?.avatar_url} alt={user?.display_name ?? ''} size="md" />

            <div className="min-w-0 flex-1">
              <textarea
                ref={textareaRef}
                value={content}
                onChange={(e) => setContent(e.target.value)}
                onInput={handleInput}
                placeholder="What's happening?"
                rows={3}
                className="w-full resize-none border-0 bg-transparent text-sm leading-relaxed text-gray-900 placeholder:text-gray-400 focus:outline-none dark:text-gray-100 dark:placeholder:text-gray-500"
                aria-label="Post content"
                maxLength={maxLength + 100} // soft limit
              />

              {/* Media previews */}
              {mediaPreviews.length > 0 && (
                <div className="mt-2 flex flex-wrap gap-2">
                  {mediaPreviews.map((src, i) => (
                    <div key={src} className="group relative h-20 w-20 overflow-hidden rounded-lg border border-gray-200 dark:border-gray-700">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img
                        src={src}
                        alt={`Upload ${i + 1}`}
                        className="h-full w-full object-cover"
                      />
                      <button
                        type="button"
                        onClick={() => removeMedia(i)}
                        className="absolute right-1 top-1 rounded-full bg-black/60 p-0.5 text-white opacity-0 transition-opacity group-hover:opacity-100"
                        aria-label={`Remove upload ${i + 1}`}
                      >
                        <X className="h-3 w-3" />
                      </button>
                    </div>
                  ))}
                </div>
              )}

              {/* Toolbar */}
              <div className="mt-3 flex items-center justify-between border-t border-gray-100 pt-3 dark:border-gray-800">
                <div className="flex items-center gap-1">
                  {/* Media upload */}
                  <input
                    ref={fileInputRef}
                    type="file"
                    accept="image/*,video/*"
                    multiple
                    className="hidden"
                    onChange={addMedia}
                    aria-label="Upload media"
                  />
                  <button
                    type="button"
                    onClick={() => fileInputRef.current?.click()}
                    className="rounded-full p-2 text-gray-500 hover:bg-gray-100 hover:text-indigo-600 dark:text-gray-400 dark:hover:bg-gray-800 dark:hover:text-indigo-400"
                    aria-label="Add image or video"
                  >
                    <ImagePlus className="h-5 w-5" />
                  </button>

                  {/* Visibility selector */}
                  <div className="relative">
                    <button
                      type="button"
                      onClick={() => setVisMenuOpen((v) => !v)}
                      className="flex items-center gap-1 rounded-full px-2 py-1 text-xs font-medium text-gray-500 hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-800"
                      aria-expanded={visMenuOpen}
                      aria-haspopup="true"
                      aria-label="Set post visibility"
                    >
                      {visibility === 'public' ? (
                        <>
                          <Globe className="h-3.5 w-3.5" /> Public
                        </>
                      ) : (
                        <>
                          <Users className="h-3.5 w-3.5" /> Followers
                        </>
                      )}
                      <ChevronDown className="h-3 w-3" />
                    </button>

                    {visMenuOpen && (
                      <div className="absolute bottom-full left-0 mb-1 w-40 rounded-lg border border-gray-200 bg-white py-1 shadow-lg dark:border-gray-700 dark:bg-gray-900">
                        <button
                          type="button"
                          onClick={() => {
                            setVisibility('public');
                            setVisMenuOpen(false);
                          }}
                          className={cn(
                            'flex w-full items-center gap-2 px-3 py-2 text-sm hover:bg-gray-50 dark:hover:bg-gray-800',
                            visibility === 'public'
                              ? 'text-indigo-600 dark:text-indigo-400'
                              : 'text-gray-700 dark:text-gray-300',
                          )}
                          role="menuitem"
                        >
                          <Globe className="h-4 w-4" /> Public
                        </button>
                        <button
                          type="button"
                          onClick={() => {
                            setVisibility('followers');
                            setVisMenuOpen(false);
                          }}
                          className={cn(
                            'flex w-full items-center gap-2 px-3 py-2 text-sm hover:bg-gray-50 dark:hover:bg-gray-800',
                            visibility === 'followers'
                              ? 'text-indigo-600 dark:text-indigo-400'
                              : 'text-gray-700 dark:text-gray-300',
                          )}
                          role="menuitem"
                        >
                          <Users className="h-4 w-4" /> Followers only
                        </button>
                      </div>
                    )}
                  </div>
                </div>

                <div className="flex items-center gap-3">
                  {/* Character count */}
                  <span
                    className={cn(
                      'text-xs tabular-nums',
                      overLimit
                        ? 'font-semibold text-red-500'
                        : charsLeft <= 100
                          ? 'text-amber-500'
                          : 'text-gray-400 dark:text-gray-500',
                    )}
                    aria-label={`${charsLeft} characters remaining`}
                  >
                    {charsLeft}
                  </span>

                  <Button
                    type="submit"
                    size="sm"
                    variant="primary"
                    disabled={!canSubmit}
                    loading={submitting}
                  >
                    Post
                  </Button>
                </div>
              </div>
            </div>
          </div>
        </form>
      )}
    </div>
  );
}
