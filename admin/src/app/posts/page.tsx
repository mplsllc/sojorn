// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import PerPageSelect from '@/components/PerPageSelect';
import SelectionBar from '@/components/SelectionBar';
import { api } from '@/lib/api';
import { statusColor, formatDate, truncate } from '@/lib/utils';
import { Suspense, useEffect, useState } from 'react';
import { Search, ChevronLeft, ChevronRight, Image, Video, MapPin, Trash2, XCircle, CheckCircle } from 'lucide-react';
import Link from 'next/link';
import { useSearchParams } from 'next/navigation';

export default function PostsPage() {
  return (
    <Suspense fallback={<AdminShell><div className="card p-8 animate-pulse"><div className="h-40 bg-warm-300 rounded" /></div></AdminShell>}>
      <PostsPageInner />
    </Suspense>
  );
}

function PostsPageInner() {
  const searchParams = useSearchParams();
  const [posts, setPosts] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [visibilityFilter, setVisibilityFilter] = useState('');
  const [mediaFilter, setMediaFilter] = useState('');
  const [sortOrder, setSortOrder] = useState('');
  const [offset, setOffset] = useState(0);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [bulkLoading, setBulkLoading] = useState(false);
  const [limit, setLimit] = useState(25);
  const authorId = searchParams.get('author_id') || undefined;

  const fetchPosts = () => {
    setLoading(true);
    api.listPosts({ limit, offset, search: search || undefined, status: statusFilter || undefined, author_id: authorId, visibility: visibilityFilter || undefined, sort: sortOrder || undefined })
      .then((data) => { setPosts(data.posts); setTotal(data.total); })
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchPosts(); }, [offset, statusFilter, visibilityFilter, sortOrder, limit]);

  const filteredPosts = mediaFilter
    ? posts.filter((p) => {
        if (mediaFilter === 'has_media') return p.image_url || p.video_url;
        if (mediaFilter === 'video') return !!p.video_url;
        if (mediaFilter === 'image') return !!p.image_url;
        return true;
      })
    : posts;

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    setOffset(0);
    fetchPosts();
  };

  const handleQuickAction = async (postId: string, action: 'remove' | 'activate') => {
    try {
      await api.updatePostStatus(postId, action === 'remove' ? 'removed' : 'active', 'Admin action');
      fetchPosts();
    } catch {}
  };

  const toggleSelect = (id: string) => {
    setSelected((prev) => { const s = new Set(prev); s.has(id) ? s.delete(id) : s.add(id); return s; });
  };
  const toggleAll = () => {
    if (selected.size === filteredPosts.length) setSelected(new Set());
    else setSelected(new Set(filteredPosts.map((p) => p.id)));
  };

  const handleBulkAction = async (action: string) => {
    setBulkLoading(true);
    try {
      await api.bulkUpdatePosts(Array.from(selected), action, 'Bulk admin action');
      setSelected(new Set());
      fetchPosts();
    } catch {}
    setBulkLoading(false);
  };

  return (
    <AdminShell>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Posts</h1>
        <p className="text-sm text-gray-500 mt-1">{total} total posts{authorId ? ' (filtered by author)' : ''}</p>
      </div>

      {/* Filters */}
      <div className="card p-4 mb-4 flex flex-wrap gap-3 items-center">
        <form onSubmit={handleSearch} className="flex-1 min-w-[200px] relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input className="input pl-10" placeholder="Search post content..." value={search} onChange={(e) => setSearch(e.target.value)} />
        </form>
        <select className="input w-auto" title="Filter by status" value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value); setOffset(0); }}>
          <option value="">All Statuses</option>
          <option value="active">Active</option>
          <option value="flagged">Flagged</option>
          <option value="removed">Removed</option>
        </select>
        <select className="input w-auto" title="Filter by visibility" value={visibilityFilter} onChange={(e) => { setVisibilityFilter(e.target.value); setOffset(0); }}>
          <option value="">All Visibility</option>
          <option value="public">Public</option>
          <option value="followers">Followers</option>
          <option value="private">Private</option>
        </select>
        <select className="input w-auto" title="Filter by media type" value={mediaFilter} onChange={(e) => { setMediaFilter(e.target.value); setOffset(0); }}>
          <option value="">All Media</option>
          <option value="has_media">Has Media</option>
          <option value="video">Video</option>
          <option value="image">Image</option>
        </select>
        <select className="input w-auto" title="Sort order" value={sortOrder} onChange={(e) => { setSortOrder(e.target.value); setOffset(0); }}>
          <option value="">Newest</option>
          <option value="oldest">Oldest</option>
          <option value="most_comments">Most Comments</option>
        </select>
      </div>

      <SelectionBar
        count={selected.size}
        total={filteredPosts.length}
        onSelectAll={() => setSelected(new Set(filteredPosts.map((p) => p.id)))}
        onClearSelection={() => setSelected(new Set())}
        loading={bulkLoading}
        actions={[
          { label: 'Remove', action: 'remove', confirm: true, color: 'bg-red-50 text-red-700 hover:bg-red-100', icon: <XCircle className="w-3.5 h-3.5" /> },
          { label: 'Activate', action: 'activate', color: 'bg-green-50 text-green-700 hover:bg-green-100', icon: <CheckCircle className="w-3.5 h-3.5" /> },
          { label: 'Delete', action: 'delete', confirm: true, color: 'bg-red-100 text-red-800 hover:bg-red-200', icon: <Trash2 className="w-3.5 h-3.5" /> },
        ]}
        onAction={handleBulkAction}
      />

      {/* Table */}
      <div className="card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-warm-200">
              <tr>
                <th className="table-header w-10">
                  <input type="checkbox" className="rounded border-gray-300" checked={filteredPosts.length > 0 && selected.size === filteredPosts.length} onChange={toggleAll} />
                </th>
                <th className="table-header">Content</th>
                <th className="table-header">Author</th>
                <th className="table-header">Media</th>
                <th className="table-header">Status</th>
                <th className="table-header">Engagement</th>
                <th className="table-header">Created</th>
                <th className="table-header">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-warm-300">
              {loading ? (
                [...Array(5)].map((_, i) => (
                  <tr key={i}>{[...Array(8)].map((_, j) => <td key={j} className="table-cell"><div className="h-4 bg-warm-300 rounded animate-pulse w-20" /></td>)}</tr>
                ))
              ) : filteredPosts.length === 0 ? (
                <tr><td colSpan={8} className="table-cell text-center text-gray-400 py-8">No posts found</td></tr>
              ) : (
                filteredPosts.map((post) => (
                  <tr key={post.id} className={`hover:bg-warm-50 transition-colors ${selected.has(post.id) ? 'bg-brand-50' : ''}`}>
                    <td className="table-cell">
                      <input type="checkbox" className="rounded border-gray-300" checked={selected.has(post.id)} onChange={() => toggleSelect(post.id)} />
                    </td>
                    <td className="table-cell max-w-xs">
                      <p className="text-sm text-gray-900 line-clamp-2">{truncate(post.body || '', 80)}</p>
                    </td>
                    <td className="table-cell">
                      <Link href={`/users/${post.author_id}`} className="text-brand-500 hover:text-brand-700 text-sm">
                        @{post.author?.handle || '—'}
                      </Link>
                    </td>
                    <td className="table-cell">
                      <div className="flex gap-1">
                        {post.image_url && <Image className="w-4 h-4 text-gray-400" />}
                        {post.video_url && <Video className="w-4 h-4 text-gray-400" />}
                        {post.is_beacon && <MapPin className="w-4 h-4 text-orange-400" />}
                      </div>
                    </td>
                    <td className="table-cell"><span className={`badge ${statusColor(post.status)}`}>{post.status}</span></td>
                    <td className="table-cell text-xs text-gray-500">
                      {post.like_count} likes · {post.comment_count} comments
                    </td>
                    <td className="table-cell text-gray-500 text-xs">{formatDate(post.created_at)}</td>
                    <td className="table-cell">
                      <div className="flex gap-2">
                        <Link href={`/posts/${post.id}`} className="text-brand-500 hover:text-brand-700 text-xs font-medium">View</Link>
                        {post.status === 'active' ? (
                          <button onClick={() => handleQuickAction(post.id, 'remove')} className="text-red-500 hover:text-red-700 text-xs font-medium">Remove</button>
                        ) : post.status === 'removed' ? (
                          <button onClick={() => handleQuickAction(post.id, 'activate')} className="text-green-500 hover:text-green-700 text-xs font-medium">Restore</button>
                        ) : null}
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
        <div className="border-t border-warm-300 px-4 py-3 flex items-center justify-between">
          <p className="text-sm text-gray-500">Showing {offset + 1}–{Math.min(offset + limit, total)} of {total}</p>
          <div className="flex items-center gap-3">
            <PerPageSelect value={limit} onChange={(n) => { setLimit(n); setOffset(0); }} />
            <button className="btn-secondary text-sm py-1.5 px-3" disabled={offset === 0} onClick={() => setOffset(Math.max(0, offset - limit))}><ChevronLeft className="w-4 h-4" /></button>
            <button className="btn-secondary text-sm py-1.5 px-3" disabled={offset + limit >= total} onClick={() => setOffset(offset + limit)}><ChevronRight className="w-4 h-4" /></button>
          </div>
        </div>
      </div>
    </AdminShell>
  );
}
