'use client';

import { forwardRef } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { cn, getInitials } from '@/lib/utils';

const sizes = {
  sm: 'h-8 w-8 text-xs',
  md: 'h-10 w-10 text-sm',
  lg: 'h-16 w-16 text-lg',
  xl: 'h-24 w-24 text-2xl',
} as const;

const pxSizes: Record<AvatarSize, number> = {
  sm: 32,
  md: 40,
  lg: 64,
  xl: 96,
};

const statusDotSizes: Record<AvatarSize, string> = {
  sm: 'h-2 w-2 border',
  md: 'h-2.5 w-2.5 border-[1.5px]',
  lg: 'h-3.5 w-3.5 border-2',
  xl: 'h-5 w-5 border-2',
};

export type AvatarSize = keyof typeof sizes;

export interface AvatarProps {
  src?: string | null;
  alt: string;
  size?: AvatarSize;
  href?: string;
  online?: boolean;
  className?: string;
}

const AvatarInner = forwardRef<HTMLDivElement, AvatarProps>(
  ({ src, alt, size = 'md', online, className }, ref) => {
    const px = pxSizes[size];
    const initials = getInitials(alt);

    return (
      <div
        ref={ref}
        className={cn('relative inline-flex shrink-0', className)}
        role="img"
        aria-label={alt}
      >
        {src ? (
          <Image
            src={src}
            alt={alt}
            width={px}
            height={px}
            className={cn(
              sizes[size],
              'rounded-full object-cover ring-2 ring-white dark:ring-gray-900',
            )}
          />
        ) : (
          <span
            className={cn(
              sizes[size],
              'inline-flex items-center justify-center rounded-full bg-indigo-100 font-semibold text-indigo-600 ring-2 ring-white dark:bg-indigo-900 dark:text-indigo-300 dark:ring-gray-900',
            )}
          >
            {initials}
          </span>
        )}

        {online !== undefined && (
          <span
            className={cn(
              statusDotSizes[size],
              'absolute bottom-0 right-0 rounded-full border-white dark:border-gray-900',
              online ? 'bg-green-500' : 'bg-gray-400',
            )}
            aria-label={online ? 'Online' : 'Offline'}
          />
        )}
      </div>
    );
  },
);

AvatarInner.displayName = 'AvatarInner';

export function Avatar(props: AvatarProps) {
  if (props.href) {
    return (
      <Link href={props.href} className="focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 rounded-full">
        <AvatarInner {...props} />
      </Link>
    );
  }

  return <AvatarInner {...props} />;
}
