import { type ReactNode } from 'react';
import Link from 'next/link';
import { cn } from '@/lib/utils';
import { Button, type ButtonProps } from '@/components/Button';

export interface EmptyStateProps {
  icon?: ReactNode;
  title: string;
  description?: string;
  action?: {
    label: string;
    onClick?: () => void;
    href?: string;
    variant?: ButtonProps['variant'];
  };
  className?: string;
}

export function EmptyState({ icon, title, description, action, className }: EmptyStateProps) {
  return (
    <div
      className={cn(
        'flex flex-col items-center justify-center px-6 py-16 text-center',
        className,
      )}
      role="status"
    >
      {icon && (
        <div className="mb-4 text-gray-400 dark:text-gray-500 [&>svg]:h-12 [&>svg]:w-12">
          {icon}
        </div>
      )}
      <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100">{title}</h3>
      {description && (
        <p className="mt-1 max-w-sm text-sm text-gray-500 dark:text-gray-400">{description}</p>
      )}
      {action && action.href ? (
        <Link href={action.href}>
          <Button
            variant={action.variant ?? 'primary'}
            size="md"
            className="mt-6"
          >
            {action.label}
          </Button>
        </Link>
      ) : action ? (
        <Button
          variant={action.variant ?? 'primary'}
          size="md"
          className="mt-6"
          onClick={action.onClick}
        >
          {action.label}
        </Button>
      ) : null}
    </div>
  );
}
