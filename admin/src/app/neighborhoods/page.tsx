// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import AdminOnlyGuard from '@/components/AdminOnlyGuard';
import { api } from '@/lib/api';
import { formatDate, truncate } from '@/lib/utils';
import { ChevronLeft, ChevronRight, Search, Shield, ShieldOff, MessageSquare, Users, Building2, Pin, PinOff, Plus, Pencil, Trash2, Save } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';

type Neighborhood = {
  id: string;
  name: string;
  city: string;
  state: string;
  zip_code: string;
  group_name: string;
  member_count: number;
  admin_count: number;
  board_post_count: number;
  group_post_count: number;
  created_at: string;
};

type NeighborhoodAdmin = {
  user_id: string;
  role: 'owner' | 'admin' | 'member';
  handle: string;
  display_name: string;
  avatar_url: string;
  joined_at: string;
};

export default function NeighborhoodsPage() {
  const [items, setItems] = useState<Neighborhood[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [zip, setZip] = useState('');
  const [state, setState] = useState('');
  const [sort, setSort] = useState<'name' | 'zip' | 'state' | 'members' | 'created'>('name');
  const [order, setOrder] = useState<'asc' | 'desc'>('asc');
  const [offset, setOffset] = useState(0);
  const [selected, setSelected] = useState<Neighborhood | null>(null);
  const [boardEntries, setBoardEntries] = useState<any[]>([]);
  const [boardLoading, setBoardLoading] = useState(false);
  const [boardSearch, setBoardSearch] = useState('');
  const [adminUserId, setAdminUserId] = useState('');
  const [adminSearchQuery, setAdminSearchQuery] = useState('');
  const [adminSearchResults, setAdminSearchResults] = useState<any[]>([]);
  const [adminSearching, setAdminSearching] = useState(false);
  const [admins, setAdmins] = useState<NeighborhoodAdmin[]>([]);
  const [adminLoading, setAdminLoading] = useState(false);
  const [showCreate, setShowCreate] = useState(false);
  const [createForm, setCreateForm] = useState({ name: '', city: '', state: '', zip_code: '', country: 'US', lat: '', lng: '', radius_meters: '1000' });
  const [editModal, setEditModal] = useState<Neighborhood | null>(null);
  const [editForm, setEditForm] = useState({ name: '', city: '', state: '', zip_code: '', radius_meters: '' });
  const [saving, setSaving] = useState(false);
  const limit = 25;

  const selectedStats = useMemo(() => {
    if (!selected) return null;
    return [
      { label: 'Members', value: selected.member_count, icon: <Users className="w-4 h-4" /> },
      { label: 'Group Admins', value: selected.admin_count, icon: <Shield className="w-4 h-4" /> },
      { label: 'Board Posts', value: selected.board_post_count, icon: <MessageSquare className="w-4 h-4" /> },
      { label: 'Group Posts', value: selected.group_post_count, icon: <Building2 className="w-4 h-4" /> },
    ];
  }, [selected]);

  const fetchNeighborhoods = () => {
    setLoading(true);
    api
      .listNeighborhoods({ limit, offset, search: search || undefined, zip: zip || undefined, state: state || undefined, sort, order })
      .then((data) => {
        setItems(data.neighborhoods || []);
        setTotal(data.total || 0);
      })
      .finally(() => setLoading(false));
  };

  const fetchBoardEntries = (id: string, searchTerm = '') => {
    setBoardLoading(true);
    api
      .listNeighborhoodBoardEntries(id, { limit: 20, offset: 0, search: searchTerm || undefined })
      .then((data) => setBoardEntries(data.entries || []))
      .finally(() => setBoardLoading(false));
  };

  const fetchNeighborhoodAdmins = (id: string) => {
    setAdminLoading(true);
    api
      .listNeighborhoodAdmins(id)
      .then((data) => setAdmins(data.admins || []))
      .finally(() => setAdminLoading(false));
  };

  useEffect(() => {
    fetchNeighborhoods();
  }, [offset, sort, order]);

  const onSearch = (e: React.FormEvent) => {
    e.preventDefault();
    setOffset(0);
    fetchNeighborhoods();
  };

  const onSelectNeighborhood = (n: Neighborhood) => {
    setSelected(n);
    setBoardSearch('');
    fetchBoardEntries(n.id);
    fetchNeighborhoodAdmins(n.id);
  };

  const toggleBoardEntry = async (entryId: string, current: boolean) => {
    if (!selected) return;
    await api.updateNeighborhoodBoardEntry(selected.id, entryId, !current);
    fetchBoardEntries(selected.id, boardSearch);
    fetchNeighborhoods();
  };

  const updateAdmin = async (action: 'assign' | 'remove') => {
    if (!selected || !adminUserId.trim()) return;
    await api.setNeighborhoodAdmin(selected.id, adminUserId.trim(), action);
    setAdminUserId('');
    setAdminSearchQuery('');
    setAdminSearchResults([]);
    fetchNeighborhoods();
    fetchNeighborhoodAdmins(selected.id);
    fetchBoardEntries(selected.id, boardSearch);
  };

  const searchAdminUsers = async (query: string) => {
    setAdminSearchQuery(query);
    setAdminUserId('');
    if (query.length < 2) { setAdminSearchResults([]); return; }
    setAdminSearching(true);
    try {
      const data = await api.listUsers({ search: query, limit: 10 });
      setAdminSearchResults(data.users || []);
    } catch { setAdminSearchResults([]); }
    setAdminSearching(false);
  };

  const selectAdminUser = (user: any) => {
    setAdminUserId(user.id);
    setAdminSearchQuery(`@${user.handle || user.display_name || user.id}`);
    setAdminSearchResults([]);
  };

  const removeAdminById = async (userId: string) => {
    if (!selected || !userId) return;
    await api.setNeighborhoodAdmin(selected.id, userId, 'remove');
    fetchNeighborhoods();
    fetchNeighborhoodAdmins(selected.id);
  };

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    try {
      await api.createNeighborhood({
        name: createForm.name,
        city: createForm.city,
        state: createForm.state,
        zip_code: createForm.zip_code,
        country: createForm.country,
        lat: parseFloat(createForm.lat),
        lng: parseFloat(createForm.lng),
        radius_meters: parseFloat(createForm.radius_meters),
      });
      setShowCreate(false);
      setCreateForm({ name: '', city: '', state: '', zip_code: '', country: 'US', lat: '', lng: '', radius_meters: '1000' });
      fetchNeighborhoods();
    } catch (e: any) {
      alert(e.message);
    }
    setSaving(false);
  };

  const openEdit = (n: Neighborhood) => {
    setEditModal(n);
    setEditForm({ name: n.name, city: n.city, state: n.state, zip_code: n.zip_code || '', radius_meters: '' });
  };

  const handleEdit = async () => {
    if (!editModal) return;
    setSaving(true);
    try {
      const data: any = {};
      if (editForm.name !== editModal.name) data.name = editForm.name;
      if (editForm.city !== editModal.city) data.city = editForm.city;
      if (editForm.state !== editModal.state) data.state = editForm.state;
      if (editForm.zip_code !== (editModal.zip_code || '')) data.zip_code = editForm.zip_code;
      if (editForm.radius_meters) data.radius_meters = parseFloat(editForm.radius_meters);
      await api.updateNeighborhood(editModal.id, data);
      setEditModal(null);
      fetchNeighborhoods();
    } catch (e: any) {
      alert(e.message);
    }
    setSaving(false);
  };

  const handleDeleteNeighborhood = async (n: Neighborhood) => {
    if (!confirm(`Delete neighborhood "${n.name}"? This will fail if users are associated.`)) return;
    try {
      await api.deleteNeighborhood(n.id);
      if (selected?.id === n.id) setSelected(null);
      fetchNeighborhoods();
    } catch (e: any) {
      alert(e.message);
    }
  };

  const toggleBoardPin = async (entryId: string, current: boolean) => {
    if (!selected) return;
    await api.pinNeighborhoodBoardEntry(selected.id, entryId, !current);
    fetchBoardEntries(selected.id, boardSearch);
  };

  return (
    <AdminOnlyGuard>
    <AdminShell>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Neighborhoods</h1>
          <p className="text-sm text-gray-500 mt-1">Search, organize, and moderate neighborhood communities by name and ZIP.</p>
        </div>
        <button type="button" onClick={() => setShowCreate(!showCreate)} className="btn-primary text-sm flex items-center gap-1">
          <Plus className="w-4 h-4" /> New Neighborhood
        </button>
      </div>

      {showCreate && (
        <form onSubmit={handleCreate} className="card p-5 mb-4 space-y-3">
          <h3 className="font-semibold text-gray-900">Create Neighborhood</h3>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <input className="input" placeholder="Name" value={createForm.name} onChange={(e) => setCreateForm({ ...createForm, name: e.target.value })} required />
            <input className="input" placeholder="City" value={createForm.city} onChange={(e) => setCreateForm({ ...createForm, city: e.target.value })} required />
            <input className="input" placeholder="State" value={createForm.state} onChange={(e) => setCreateForm({ ...createForm, state: e.target.value })} required />
          </div>
          <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
            <input className="input" placeholder="ZIP Code" value={createForm.zip_code} onChange={(e) => setCreateForm({ ...createForm, zip_code: e.target.value })} />
            <input className="input" placeholder="Latitude" type="number" step="any" value={createForm.lat} onChange={(e) => setCreateForm({ ...createForm, lat: e.target.value })} required />
            <input className="input" placeholder="Longitude" type="number" step="any" value={createForm.lng} onChange={(e) => setCreateForm({ ...createForm, lng: e.target.value })} required />
            <input className="input" placeholder="Radius (meters)" type="number" value={createForm.radius_meters} onChange={(e) => setCreateForm({ ...createForm, radius_meters: e.target.value })} required />
          </div>
          <div className="flex gap-2">
            <button type="button" onClick={() => setShowCreate(false)} className="btn-secondary text-sm">Cancel</button>
            <button type="submit" disabled={saving} className="btn-primary text-sm">{saving ? 'Creating...' : 'Create'}</button>
          </div>
        </form>
      )}

      <div className="card p-4 mb-4 flex flex-wrap gap-3 items-center">
        <form onSubmit={onSearch} className="flex-1 min-w-[220px] relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input
            className="input pl-10"
            placeholder="Search neighborhood, city, state, ZIP..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </form>
        <input
          className="input w-32"
          placeholder="State"
          value={state}
          onChange={(e) => setState(e.target.value)}
        />
        <input
          className="input w-32"
          placeholder="ZIP"
          value={zip}
          onChange={(e) => setZip(e.target.value)}
        />
        <select className="input w-auto" value={sort} onChange={(e) => setSort(e.target.value as any)}>
          <option value="name">Sort: Name</option>
          <option value="state">Sort: State</option>
          <option value="zip">Sort: ZIP</option>
          <option value="members">Sort: Members</option>
          <option value="created">Sort: Created</option>
        </select>
        <select className="input w-auto" value={order} onChange={(e) => setOrder(e.target.value as any)}>
          <option value="asc">Asc</option>
          <option value="desc">Desc</option>
        </select>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-[1.4fr,1fr] gap-4">
        <div className="card overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-warm-200">
                <tr>
                  <th className="table-header">Neighborhood</th>
                  <th className="table-header">State</th>
                  <th className="table-header">ZIP</th>
                  <th className="table-header">Members</th>
                  <th className="table-header">Admins</th>
                  <th className="table-header">Board</th>
                  <th className="table-header">Group</th>
                  <th className="table-header">Created</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-warm-300">
                {loading ? (
                  [...Array(6)].map((_, i) => (
                    <tr key={i}>{[...Array(8)].map((__, j) => <td key={j} className="table-cell"><div className="h-4 bg-warm-300 rounded animate-pulse w-20" /></td>)}</tr>
                  ))
                ) : items.length === 0 ? (
                  <tr><td colSpan={8} className="table-cell text-center text-gray-400 py-8">No neighborhoods found</td></tr>
                ) : (
                  items.map((n) => (
                    <tr key={n.id} className={`hover:bg-warm-50 cursor-pointer ${selected?.id === n.id ? 'bg-brand-50' : ''}`} onClick={() => onSelectNeighborhood(n)}>
                      <td className="table-cell">
                        <div>
                          <p className="font-medium text-gray-900">{n.name}</p>
                          <p className="text-xs text-gray-500">{truncate(n.city, 25)}</p>
                        </div>
                      </td>
                      <td className="table-cell text-gray-600">{n.state || '—'}</td>
                      <td className="table-cell">{n.zip_code || '—'}</td>
                      <td className="table-cell">{n.member_count}</td>
                      <td className="table-cell">{n.admin_count}</td>
                      <td className="table-cell">{n.board_post_count}</td>
                      <td className="table-cell">{n.group_post_count}</td>
                      <td className="table-cell text-gray-500 text-xs">{formatDate(n.created_at)}</td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
          <div className="border-t border-warm-300 px-4 py-3 flex items-center justify-between">
            <p className="text-sm text-gray-500">Showing {Math.min(offset + 1, total)}–{Math.min(offset + limit, total)} of {total}</p>
            <div className="flex gap-2">
              <button className="btn-secondary text-sm py-1.5 px-3" disabled={offset === 0} onClick={() => setOffset(Math.max(0, offset - limit))}><ChevronLeft className="w-4 h-4" /></button>
              <button className="btn-secondary text-sm py-1.5 px-3" disabled={offset + limit >= total} onClick={() => setOffset(offset + limit)}><ChevronRight className="w-4 h-4" /></button>
            </div>
          </div>
        </div>

        <div className="card p-4 min-h-[300px]">
          {!selected ? (
            <p className="text-sm text-gray-500">Select a neighborhood to manage admins and board content.</p>
          ) : (
            <div className="space-y-4">
              <div className="flex items-start justify-between">
                <div>
                  <h2 className="text-lg font-semibold text-gray-900">{selected.name}</h2>
                  <p className="text-sm text-gray-500">{selected.city}, {selected.state} {selected.zip_code ? `· ${selected.zip_code}` : ''}</p>
                </div>
                <div className="flex gap-1">
                  <button type="button" onClick={() => openEdit(selected)} className="text-brand-500 hover:text-brand-700 p-1" title="Edit neighborhood">
                    <Pencil className="w-4 h-4" />
                  </button>
                  <button type="button" onClick={() => handleDeleteNeighborhood(selected)} className="text-red-500 hover:text-red-700 p-1" title="Delete neighborhood">
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-2">
                {selectedStats?.map((stat) => (
                  <div key={stat.label} className="rounded-lg border border-warm-300 p-2 bg-warm-100">
                    <div className="flex items-center gap-2 text-gray-500 text-xs">{stat.icon}<span>{stat.label}</span></div>
                    <p className="text-lg font-semibold text-gray-900">{stat.value}</p>
                  </div>
                ))}
              </div>

              <div className="border border-warm-300 rounded-lg p-3 bg-warm-50">
                <p className="text-xs font-semibold uppercase tracking-wide text-gray-500 mb-2">Neighborhood Admins</p>
                <div className="relative">
                  <div className="flex gap-2">
                    <div className="relative flex-1">
                      <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-gray-400" />
                      <input
                        className="input pl-8"
                        placeholder="Search by handle or name..."
                        value={adminSearchQuery}
                        onChange={(e) => searchAdminUsers(e.target.value)}
                        onFocus={() => { if (adminSearchQuery.length >= 2) searchAdminUsers(adminSearchQuery); }}
                      />
                      {adminSearchResults.length > 0 && (
                        <div className="absolute z-20 left-0 right-0 top-full mt-1 bg-white border border-warm-300 rounded-lg shadow-lg max-h-48 overflow-y-auto">
                          {adminSearchResults.map((u: any) => (
                            <button
                              key={u.id}
                              type="button"
                              className="w-full text-left px-3 py-2 hover:bg-warm-50 border-b border-warm-100 last:border-0"
                              onClick={() => selectAdminUser(u)}
                            >
                              <p className="text-sm font-medium text-gray-900">{u.display_name || u.handle}</p>
                              <p className="text-xs text-gray-500">@{u.handle} · {u.email}</p>
                            </button>
                          ))}
                        </div>
                      )}
                      {adminSearching && <p className="absolute z-20 left-0 right-0 top-full mt-1 bg-white border border-warm-300 rounded-lg shadow-lg px-3 py-2 text-xs text-gray-500">Searching…</p>}
                    </div>
                    <button className="btn-primary text-sm whitespace-nowrap" disabled={!adminUserId} onClick={() => updateAdmin('assign')}><Shield className="w-4 h-4" />Assign</button>
                    <button className="btn-secondary text-sm whitespace-nowrap" disabled={!adminUserId} onClick={() => updateAdmin('remove')}><ShieldOff className="w-4 h-4" />Remove</button>
                  </div>
                </div>
                <div className="mt-3 rounded-lg border border-warm-300 bg-white overflow-hidden">
                  <div className="px-3 py-2 border-b border-warm-200 text-xs font-semibold text-gray-600">Current Moderators</div>
                  {adminLoading ? (
                    <p className="px-3 py-2 text-xs text-gray-500">Loading moderators…</p>
                  ) : admins.length === 0 ? (
                    <p className="px-3 py-2 text-xs text-gray-500">No admins found for this neighborhood.</p>
                  ) : (
                    admins.map((mod) => (
                      <div key={mod.user_id} className="px-3 py-2 border-b border-warm-100 last:border-0 flex items-center justify-between gap-2">
                        <div>
                          <p className="text-sm font-medium text-gray-800">{mod.display_name || mod.handle || mod.user_id}</p>
                          <p className="text-xs text-gray-500">@{mod.handle || 'unknown'} · {mod.role}</p>
                        </div>
                        {mod.role === 'admin' && (
                          <button className="text-xs text-red-600 hover:text-red-700 font-medium" onClick={() => removeAdminById(mod.user_id)}>
                            Remove
                          </button>
                        )}
                      </div>
                    ))
                  )}
                </div>
              </div>

              <div className="border border-warm-300 rounded-lg overflow-hidden">
                <div className="p-3 bg-warm-100 border-b border-warm-300 flex items-center justify-between">
                  <p className="text-sm font-semibold text-gray-700">Board Moderation</p>
                  <form
                    className="relative"
                    onSubmit={(e) => {
                      e.preventDefault();
                      if (selected) fetchBoardEntries(selected.id, boardSearch);
                    }}
                  >
                    <Search className="absolute left-2 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-gray-400" />
                    <input className="input h-8 pl-7 text-xs" placeholder="Search posts" value={boardSearch} onChange={(e) => setBoardSearch(e.target.value)} />
                  </form>
                </div>
                <div className="max-h-80 overflow-y-auto">
                  {boardLoading ? (
                    <p className="p-3 text-xs text-gray-500">Loading board entries…</p>
                  ) : boardEntries.length === 0 ? (
                    <p className="p-3 text-xs text-gray-500">No board entries in this neighborhood.</p>
                  ) : (
                    boardEntries.map((entry) => (
                      <div key={entry.id} className="p-3 border-b border-warm-200 last:border-0">
                        <p className="text-sm text-gray-900 line-clamp-2">{entry.body}</p>
                        <div className="mt-1 text-xs text-gray-500 flex items-center justify-between">
                          <span>@{entry.author?.handle || 'unknown'} · {entry.topic || 'community'}</span>
                          <span>{entry.upvotes || 0}↑ · {entry.reply_count || 0} replies</span>
                        </div>
                        <div className="mt-2">
                          <div className="flex items-center gap-3">
                            <button
                              className={`text-xs font-medium ${entry.is_active ? 'text-red-600 hover:text-red-700' : 'text-green-600 hover:text-green-700'}`}
                              onClick={() => toggleBoardEntry(entry.id, !!entry.is_active)}
                            >
                              {entry.is_active ? 'Hide post' : 'Restore post'}
                            </button>
                            <button
                              className={`text-xs font-medium inline-flex items-center gap-1 ${entry.is_pinned ? 'text-orange-600 hover:text-orange-700' : 'text-brand-600 hover:text-brand-700'}`}
                              onClick={() => toggleBoardPin(entry.id, !!entry.is_pinned)}
                            >
                              {entry.is_pinned ? <PinOff className="w-3.5 h-3.5" /> : <Pin className="w-3.5 h-3.5" />}
                              {entry.is_pinned ? 'Unpin' : 'Pin'}
                            </button>
                          </div>
                        </div>
                      </div>
                    ))
                  )}
                </div>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Edit Neighborhood Modal */}
      {editModal && (
        <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50" onClick={() => setEditModal(null)}>
          <div className="bg-white rounded-xl p-6 w-full max-w-md mx-4 shadow-xl" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-lg font-semibold text-gray-900 mb-4">Edit Neighborhood</h3>
            <div className="space-y-3">
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Name</label>
                <input className="w-full px-3 py-2 border rounded-lg text-sm" title="Neighborhood name" value={editForm.name} onChange={(e) => setEditForm({ ...editForm, name: e.target.value })} />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-gray-500 mb-1">City</label>
                  <input className="w-full px-3 py-2 border rounded-lg text-sm" title="City" value={editForm.city} onChange={(e) => setEditForm({ ...editForm, city: e.target.value })} />
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-500 mb-1">State</label>
                  <input className="w-full px-3 py-2 border rounded-lg text-sm" title="State" value={editForm.state} onChange={(e) => setEditForm({ ...editForm, state: e.target.value })} />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-gray-500 mb-1">ZIP Code</label>
                  <input className="w-full px-3 py-2 border rounded-lg text-sm" title="ZIP code" value={editForm.zip_code} onChange={(e) => setEditForm({ ...editForm, zip_code: e.target.value })} />
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-500 mb-1">Radius (meters)</label>
                  <input className="w-full px-3 py-2 border rounded-lg text-sm" title="Radius in meters" type="number" placeholder="Leave blank to keep current" value={editForm.radius_meters} onChange={(e) => setEditForm({ ...editForm, radius_meters: e.target.value })} />
                </div>
              </div>
            </div>
            <div className="flex gap-2 justify-end mt-5">
              <button type="button" onClick={() => setEditModal(null)} className="px-4 py-2 text-sm text-gray-600 hover:text-gray-800">Cancel</button>
              <button type="button" onClick={handleEdit} disabled={saving} className="btn-primary text-sm flex items-center gap-1">
                <Save className="w-4 h-4" /> {saving ? 'Saving...' : 'Save'}
              </button>
            </div>
          </div>
        </div>
      )}
    </AdminShell>
    </AdminOnlyGuard>
  );
}
