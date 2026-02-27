// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import AdminOnlyGuard from '@/components/AdminOnlyGuard';
import { api } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';
import { useEffect, useState } from 'react';
import { Search, Calendar, Trash2, Pencil, Save, X } from 'lucide-react';

export default function EventsPage() {
  const [events, setEvents] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [offset, setOffset] = useState(0);
  const [editEvent, setEditEvent] = useState<any | null>(null);
  const [editForm, setEditForm] = useState({ title: '', description: '', status: '' });
  const [editSaving, setEditSaving] = useState(false);
  const limit = 50;

  const fetchEvents = () => {
    setLoading(true);
    api.listEvents({ search: search || undefined, status: statusFilter || undefined, limit, offset })
      .then((data) => setEvents(data.events ?? []))
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchEvents(); }, [offset]);

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    setOffset(0);
    fetchEvents();
  };

  const openEdit = (ev: any) => {
    setEditEvent(ev);
    setEditForm({ title: ev.title, description: ev.description || '', status: ev.status });
  };

  const saveEdit = async () => {
    if (!editEvent) return;
    setEditSaving(true);
    try {
      await api.updateEvent(editEvent.id, editForm);
      setEditEvent(null);
      fetchEvents();
    } catch (e: any) {
      alert(e.message);
    }
    setEditSaving(false);
  };

  const handleDelete = async (id: string, title: string) => {
    if (!confirm(`Delete event "${title}"? This will also remove all RSVPs.`)) return;
    try {
      await api.deleteEvent(id);
      fetchEvents();
    } catch (e: any) {
      alert(e.message);
    }
  };

  const statusColor = (s: string) => {
    switch (s) {
      case 'active': return 'bg-green-100 text-green-700';
      case 'cancelled': return 'bg-orange-100 text-orange-700';
      case 'completed': return 'bg-gray-100 text-gray-600';
      default: return 'bg-gray-100 text-gray-600';
    }
  };

  return (
    <AdminOnlyGuard>
    <AdminShell>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Events</h1>
        <p className="text-sm text-gray-500 mt-1">Manage group events and RSVPs</p>
      </div>

      <form onSubmit={handleSearch} className="mb-4 flex gap-2 items-center">
        <div className="relative flex-1 max-w-md">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 w-4 h-4" />
          <input
            className="pl-9 pr-4 py-2 border rounded-lg w-full text-sm"
            placeholder="Search events..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <select
          className="px-3 py-2 border rounded-lg text-sm"
          title="Filter by status"
          value={statusFilter}
          onChange={(e) => { setStatusFilter(e.target.value); setOffset(0); }}
        >
          <option value="">All Statuses</option>
          <option value="active">Active</option>
          <option value="cancelled">Cancelled</option>
          <option value="completed">Completed</option>
        </select>
        <button type="submit" className="px-4 py-2 bg-blue-700 text-white rounded-lg text-sm font-medium hover:bg-blue-800">
          Search
        </button>
      </form>

      <div className="card overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-gray-400">Loading…</div>
        ) : events.length === 0 ? (
          <div className="p-12 text-center">
            <Calendar className="w-12 h-12 text-gray-300 mx-auto mb-3" />
            <p className="text-gray-500">No events found</p>
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-gray-600">Event</th>
                <th className="px-4 py-3 text-left font-medium text-gray-600">Group</th>
                <th className="px-4 py-3 text-center font-medium text-gray-600">Status</th>
                <th className="px-4 py-3 text-center font-medium text-gray-600">RSVPs</th>
                <th className="px-4 py-3 text-left font-medium text-gray-600">Starts</th>
                <th className="px-4 py-3 text-left font-medium text-gray-600">Created</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {events.map((ev) => (
                <tr key={ev.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3">
                    <p className="font-medium text-gray-900 truncate max-w-xs">{ev.title}</p>
                    {ev.location_name && <p className="text-xs text-gray-400 truncate">{ev.location_name}</p>}
                  </td>
                  <td className="px-4 py-3 text-gray-600">{ev.group_name || '—'}</td>
                  <td className="px-4 py-3 text-center">
                    <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${statusColor(ev.status)}`}>
                      {ev.status}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-center">{ev.rsvp_count ?? 0}</td>
                  <td className="px-4 py-3 text-gray-500 text-xs">{ev.starts_at ? formatDateTime(ev.starts_at) : '—'}</td>
                  <td className="px-4 py-3 text-gray-500 text-xs">{formatDateTime(ev.created_at)}</td>
                  <td className="px-4 py-3 text-right">
                    <div className="flex items-center justify-end gap-1">
                      <button
                        type="button"
                        onClick={() => openEdit(ev)}
                        className="text-brand-500 hover:text-brand-700 p-1"
                        title="Edit event"
                      >
                        <Pencil className="w-4 h-4" />
                      </button>
                      <button
                        type="button"
                        onClick={() => handleDelete(ev.id, ev.title)}
                        className="text-red-500 hover:text-red-700 p-1"
                        title="Delete event"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        <div className="px-4 py-3 border-t flex items-center gap-3">
          <button type="button" disabled={offset === 0} onClick={() => setOffset(Math.max(0, offset - limit))}
            className="text-sm px-3 py-1.5 rounded border disabled:opacity-40">Prev</button>
          <button type="button" disabled={events.length < limit} onClick={() => setOffset(offset + limit)}
            className="text-sm px-3 py-1.5 rounded border disabled:opacity-40">Next</button>
        </div>
      </div>

      {/* Edit Event Modal */}
      {editEvent && (
        <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50" onClick={() => setEditEvent(null)}>
          <div className="bg-white rounded-xl p-6 w-full max-w-md mx-4 shadow-xl" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-lg font-semibold text-gray-900 mb-4">Edit Event</h3>
            <div className="space-y-3">
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Title</label>
                <input className="w-full px-3 py-2 border rounded-lg text-sm" title="Event title" value={editForm.title} onChange={(e) => setEditForm({ ...editForm, title: e.target.value })} />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Description</label>
                <textarea className="w-full px-3 py-2 border rounded-lg text-sm" title="Event description" rows={3} value={editForm.description} onChange={(e) => setEditForm({ ...editForm, description: e.target.value })} />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Status</label>
                <select className="w-full px-3 py-2 border rounded-lg text-sm" title="Event status" value={editForm.status} onChange={(e) => setEditForm({ ...editForm, status: e.target.value })}>
                  <option value="active">Active</option>
                  <option value="cancelled">Cancelled</option>
                  <option value="completed">Completed</option>
                </select>
              </div>
            </div>
            <div className="flex gap-2 justify-end mt-5">
              <button type="button" onClick={() => setEditEvent(null)} className="px-4 py-2 text-sm text-gray-600 hover:text-gray-800">Cancel</button>
              <button type="button" onClick={saveEdit} disabled={editSaving} className="btn-primary text-sm flex items-center gap-1">
                <Save className="w-4 h-4" /> {editSaving ? 'Saving...' : 'Save'}
              </button>
            </div>
          </div>
        </div>
      )}
    </AdminShell>
    </AdminOnlyGuard>
  );
}
