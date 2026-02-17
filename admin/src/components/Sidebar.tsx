'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useAuth } from '@/lib/auth';
import { cn } from '@/lib/utils';
import {
  LayoutDashboard, Users, FileText, Shield, ShieldCheck, Scale, Flag,
  Settings, Activity, LogOut, ChevronLeft, ChevronRight, ChevronDown,
  Sliders, FolderTree, HardDrive, AtSign, Brain, ScrollText, Wrench, Bot,
  UserCog, ShieldAlert, Cog, Mail, MapPinned, Users2, Video, ClipboardList, Clock,
} from 'lucide-react';
import { useState } from 'react';

type NavItem = { href: string; label: string; icon: any };
type NavGroup = { label: string; icon: any; items: NavItem[] };
type NavEntry = NavItem | NavGroup;

function isGroup(entry: NavEntry): entry is NavGroup {
  return 'items' in entry;
}

const navigation: NavEntry[] = [
  { href: '/', label: 'Dashboard', icon: LayoutDashboard },
  {
    label: 'Users & Content',
    icon: UserCog,
    items: [
      { href: '/users', label: 'Users', icon: Users },
      { href: '/posts', label: 'Posts', icon: FileText },
      { href: '/categories', label: 'Categories', icon: FolderTree },
      { href: '/neighborhoods', label: 'Neighborhoods', icon: MapPinned },
      { href: '/official-accounts', label: 'Official Accounts', icon: Bot },
      { href: '/groups', label: 'Groups & Capsules', icon: Users2 },
      { href: '/waitlist', label: 'Waitlist', icon: Clock },
    ],
  },
  {
    label: 'Moderation & Safety',
    icon: ShieldAlert,
    items: [
      { href: '/safety', label: 'Safety Workspace', icon: ShieldAlert },
      { href: '/moderation', label: 'Moderation Queue', icon: Shield },
      { href: '/ai-moderation', label: 'AI Moderation', icon: Brain },
      { href: '/ai-audit-log', label: 'AI Audit Log', icon: ScrollText },
      { href: '/appeals', label: 'Appeals', icon: Scale },
      { href: '/reports', label: 'Reports', icon: Flag },
      { href: '/safe-links', label: 'Safe Links', icon: ShieldCheck },
      { href: '/content-tools', label: 'Content Tools', icon: Wrench },
    ],
  },
  {
    label: 'Platform',
    icon: Cog,
    items: [
      { href: '/algorithm', label: 'Algorithm', icon: Sliders },
      { href: '/usernames', label: 'Usernames', icon: AtSign },
      { href: '/storage', label: 'Storage', icon: HardDrive },
      { href: '/system', label: 'System Health', icon: Activity },
      { href: '/audit-log', label: 'Audit Log', icon: ClipboardList },
      { href: '/quips', label: 'Quip Repair', icon: Video },
      { href: '/settings/emails', label: 'Email Templates', icon: Mail },
      { href: '/settings', label: 'Settings', icon: Settings },
    ],
  },
];

function NavGroupSection({
  group,
  pathname,
  collapsed,
  open,
  onToggle,
}: {
  group: NavGroup;
  pathname: string;
  collapsed: boolean;
  open: boolean;
  onToggle: () => void;
}) {
  const Icon = group.icon;
  const hasActive = group.items.some(
    (item) => pathname === item.href || pathname.startsWith(item.href)
  );

  return (
    <div className="mb-1">
      <button
        onClick={onToggle}
        className={cn(
          'flex items-center w-full px-4 py-2 mx-2 rounded-lg text-xs font-semibold uppercase tracking-wider transition-colors',
          collapsed ? 'justify-center' : 'justify-between',
          hasActive ? 'text-brand-600' : 'text-gray-400 hover:text-gray-600'
        )}
        style={{ maxWidth: collapsed ? '48px' : 'calc(100% - 16px)' }}
        title={collapsed ? group.label : undefined}
      >
        <div className="flex items-center">
          <Icon className="w-4 h-4 flex-shrink-0" />
          {!collapsed && <span className="ml-2">{group.label}</span>}
        </div>
        {!collapsed && (
          <ChevronDown
            className={cn(
              'w-3.5 h-3.5 transition-transform duration-200',
              open ? 'rotate-0' : '-rotate-90'
            )}
          />
        )}
      </button>
      {(open || collapsed) && (
        <div className={collapsed ? '' : 'ml-2'}>
          {group.items.map((item) => {
            const isActive =
              pathname === item.href || pathname.startsWith(item.href);
            const ItemIcon = item.icon;
            return (
              <Link
                key={item.href}
                href={item.href}
                className={cn(
                  'flex items-center px-4 py-2 mx-2 rounded-lg text-sm font-medium transition-colors mb-0.5',
                  isActive
                    ? 'bg-brand-50 text-brand-600'
                    : 'text-gray-600 hover:bg-warm-200 hover:text-gray-900'
                )}
                title={collapsed ? item.label : undefined}
              >
                <ItemIcon className="w-5 h-5 flex-shrink-0" />
                {!collapsed && <span className="ml-3">{item.label}</span>}
              </Link>
            );
          })}
        </div>
      )}
    </div>
  );
}

export default function Sidebar() {
  const pathname = usePathname();
  const { logout } = useAuth();
  const [collapsed, setCollapsed] = useState(false);
  const [openGroups, setOpenGroups] = useState<Record<string, boolean>>(() => {
    // All groups open by default
    const defaults: Record<string, boolean> = {};
    navigation.forEach((entry) => {
      if (isGroup(entry)) defaults[entry.label] = true;
    });
    return defaults;
  });

  const toggleGroup = (label: string) => {
    setOpenGroups((prev) => ({ ...prev, [label]: !prev[label] }));
  };

  return (
    <aside
      className={cn(
        'fixed left-0 top-0 h-screen bg-white border-r border-warm-300 flex flex-col transition-all duration-300 z-30',
        collapsed ? 'w-16' : 'w-60'
      )}
    >
      {/* Logo */}
      <div className="h-16 flex items-center px-4 border-b border-warm-300">
        <div className="w-8 h-8 bg-brand-500 rounded-lg flex items-center justify-center flex-shrink-0">
          <span className="text-white font-bold text-sm">S</span>
        </div>
        {!collapsed && <span className="ml-3 font-semibold text-gray-900">Sojorn Admin</span>}
      </div>

      {/* Navigation */}
      <nav className="flex-1 py-4 overflow-y-auto">
        {navigation.map((entry) => {
          if (isGroup(entry)) {
            return (
              <NavGroupSection
                key={entry.label}
                group={entry}
                pathname={pathname}
                collapsed={collapsed}
                open={!!openGroups[entry.label]}
                onToggle={() => toggleGroup(entry.label)}
              />
            );
          }
          const item = entry;
          const isActive = pathname === item.href || (item.href !== '/' && pathname.startsWith(item.href));
          const Icon = item.icon;
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                'flex items-center px-4 py-2.5 mx-2 rounded-lg text-sm font-medium transition-colors mb-1',
                isActive
                  ? 'bg-brand-50 text-brand-600'
                  : 'text-gray-600 hover:bg-warm-200 hover:text-gray-900'
              )}
              title={collapsed ? item.label : undefined}
            >
              <Icon className="w-5 h-5 flex-shrink-0" />
              {!collapsed && <span className="ml-3">{item.label}</span>}
            </Link>
          );
        })}
      </nav>

      {/* Footer */}
      <div className="border-t border-warm-300 p-3">
        <button
          onClick={() => setCollapsed(!collapsed)}
          className="flex items-center px-2 py-2 w-full rounded-lg text-sm text-gray-500 hover:bg-warm-200 transition-colors"
        >
          {collapsed ? <ChevronRight className="w-5 h-5" /> : <ChevronLeft className="w-5 h-5" />}
          {!collapsed && <span className="ml-3">Collapse</span>}
        </button>
        <button
          onClick={logout}
          className="flex items-center px-2 py-2 w-full rounded-lg text-sm text-red-600 hover:bg-red-50 transition-colors mt-1"
        >
          <LogOut className="w-5 h-5 flex-shrink-0" />
          {!collapsed && <span className="ml-3">Sign Out</span>}
        </button>
      </div>
    </aside>
  );
}
