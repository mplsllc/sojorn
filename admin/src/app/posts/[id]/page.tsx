'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { statusColor, formatDateTime } from '@/lib/utils';
import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { ArrowLeft, Image, Video, MapPin, Trash2, CheckCircle, AlertTriangle } from 'lucide-react';
import Link from 'next/link';

export default function PostDetailPage() {
  const params = useParams();
  const router = useRouter();
  const [post, setPost] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  const fetchPost = () => {
    setLoading(true);
    api.getPost(params.id as string)
      .then(setPost)
      .catch(() => router.push('/posts'))
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchPost(); }, [params.id]);

  const handleStatusChange = async (status: string) => {
    try {
      await api.updatePostStatus(params.id as string, status, 'Admin action');
      fetchPost();
    } catch {}
  };

  const handleDelete = async () => {
    if (!confirm('Are you sure you want to delete this post?')) return;
    try {
      await api.deletePost(params.id as string);
      router.push('/posts');
    } catch {}
  };

  return (
    <AdminShell>
      <Link href="/posts" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 mb-4">
        <ArrowLeft className="w-4 h-4" /> Back to Posts
      </Link>

      {loading ? (
        <div className="card p-8 animate-pulse"><div className="h-40 bg-warm-300 rounded" /></div>
      ) : post ? (
        <div className="space-y-6">
          {/* Header */}
          <div className="card p-6">
            <div className="flex items-start justify-between mb-4">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 bg-brand-100 rounded-full flex items-center justify-center text-brand-600 text-sm font-bold">
                  {(post.author?.handle || '?')[0].toUpperCase()}
                </div>
                <div>
                  <Link href={`/users/${post.author_id}`} className="font-medium text-gray-900 hover:text-brand-600">
                    {post.author?.display_name || post.author?.handle || '—'}
                  </Link>
                  <p className="text-xs text-gray-400">@{post.author?.handle || '—'} · {formatDateTime(post.created_at)}</p>
                </div>
              </div>
              <div className="flex items-center gap-2">
                <span className={`badge ${statusColor(post.status)}`}>{post.status}</span>
                {post.is_beacon && <span className="badge bg-orange-100 text-orange-700"><MapPin className="w-3 h-3 mr-1" /> Beacon</span>}
                {post.visibility !== 'public' && <span className="badge bg-gray-100 text-gray-600">{post.visibility}</span>}
              </div>
            </div>

            {/* Content */}
            <div className="bg-warm-100 rounded-lg p-4 mb-4">
              <p className="text-gray-800 whitespace-pre-wrap">{post.body || 'No text content'}</p>
            </div>

            {/* Media */}
            <div className="flex flex-wrap gap-3 mb-4">
              {post.image_url && (
                <div className="flex items-center gap-2 text-sm text-gray-500 bg-warm-200 rounded-lg px-3 py-2">
                  <Image className="w-4 h-4" />
                  <a href={post.image_url} target="_blank" rel="noopener noreferrer" className="text-brand-500 hover:text-brand-700 truncate max-w-xs">
                    {post.image_url}
                  </a>
                </div>
              )}
              {post.video_url && (
                <div className="flex items-center gap-2 text-sm text-gray-500 bg-warm-200 rounded-lg px-3 py-2">
                  <Video className="w-4 h-4" />
                  <a href={post.video_url} target="_blank" rel="noopener noreferrer" className="text-brand-500 hover:text-brand-700 truncate max-w-xs">
                    {post.video_url}
                  </a>
                </div>
              )}
            </div>

            {/* Stats */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
              {[
                { label: 'Likes', value: post.like_count },
                { label: 'Comments', value: post.comment_count },
                { label: 'Duration', value: post.duration_ms ? `${(post.duration_ms / 1000).toFixed(1)}s` : '—' },
                { label: 'Format', value: post.body_format || 'plain' },
              ].map((s) => (
                <div key={s.label} className="bg-warm-100 rounded-lg p-3 text-center">
                  <p className="text-lg font-bold text-gray-900">{s.value ?? 0}</p>
                  <p className="text-xs text-gray-500">{s.label}</p>
                </div>
              ))}
            </div>

            {/* Metadata */}
            <div className="text-xs text-gray-400 space-y-1">
              {post.tone_label && <p>Tone: {post.tone_label} {post.cis_score != null ? `(CIS: ${(post.cis_score * 100).toFixed(0)}%)` : ''}</p>}
              {post.edited_at && <p>Edited: {formatDateTime(post.edited_at)}</p>}
              {post.beacon_type && <p>Beacon type: {post.beacon_type}</p>}
              <p>Allow chain: {post.allow_chain ? 'Yes' : 'No'}</p>
              <p>Post ID: {post.id}</p>
            </div>
          </div>

          {/* Moderation Flags */}
          {post.moderation_flags && post.moderation_flags.length > 0 && (
            <div className="card p-5">
              <h3 className="text-sm font-semibold text-gray-700 mb-3 flex items-center gap-2">
                <AlertTriangle className="w-4 h-4 text-orange-500" /> Moderation Flags ({post.moderation_flags.length})
              </h3>
              <div className="space-y-3">
                {post.moderation_flags.map((flag: any) => (
                  <div key={flag.id} className="bg-warm-100 rounded-lg p-3">
                    <div className="flex items-center gap-2 mb-1">
                      <span className={`badge ${statusColor(flag.status)}`}>{flag.status}</span>
                      <span className="badge bg-red-50 text-red-700">{flag.flag_reason}</span>
                      <span className="text-xs text-gray-400">{formatDateTime(flag.created_at)}</span>
                    </div>
                    {flag.scores && (
                      <div className="flex gap-4 text-xs text-gray-500 mt-1">
                        {Object.entries(flag.scores).map(([key, value]) => (
                          <span key={key}>{key}: {((value as number) * 100).toFixed(0)}%</span>
                        ))}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Actions */}
          <div className="card p-5">
            <h3 className="text-sm font-semibold text-gray-700 mb-3">Admin Actions</h3>
            <div className="flex flex-wrap gap-2">
              {post.status !== 'active' && (
                <button onClick={() => handleStatusChange('active')} className="btn-primary text-sm flex items-center gap-1">
                  <CheckCircle className="w-4 h-4" /> Restore / Activate
                </button>
              )}
              {post.status === 'active' && (
                <button onClick={() => handleStatusChange('flagged')} className="bg-yellow-500 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-yellow-600 flex items-center gap-1">
                  <AlertTriangle className="w-4 h-4" /> Flag
                </button>
              )}
              {post.status !== 'removed' && (
                <button onClick={() => handleStatusChange('removed')} className="bg-orange-500 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-orange-600 flex items-center gap-1">
                  <Trash2 className="w-4 h-4" /> Remove
                </button>
              )}
              <button onClick={handleDelete} className="btn-danger text-sm flex items-center gap-1">
                <Trash2 className="w-4 h-4" /> Permanently Delete
              </button>
            </div>
          </div>
        </div>
      ) : (
        <div className="card p-8 text-center text-gray-500">Post not found</div>
      )}
    </AdminShell>
  );
}
