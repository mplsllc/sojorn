// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { formatDate } from '@/lib/utils';
import { useEffect, useState } from 'react';
import { FolderTree, Plus, Save, Trash2 } from 'lucide-react';

export default function CategoriesPage() {
  const [categories, setCategories] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [showCreate, setShowCreate] = useState(false);
  const [newCat, setNewCat] = useState({ slug: '', name: '', description: '', is_sensitive: false });
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editData, setEditData] = useState({ name: '', description: '', is_sensitive: false });

  const fetchCategories = () => {
    setLoading(true);
    api.listCategories()
      .then((data) => setCategories(data.categories || []))
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchCategories(); }, []);

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await api.createCategory(newCat);
      setShowCreate(false);
      setNewCat({ slug: '', name: '', description: '', is_sensitive: false });
      fetchCategories();
    } catch {}
  };

  const handleUpdate = async (id: string) => {
    try {
      await api.updateCategory(id, editData);
      setEditingId(null);
      fetchCategories();
    } catch {}
  };

  const handleDelete = async (id: string, name: string) => {
    if (!confirm(`Delete category "${name}"? Posts using it will become uncategorized.`)) return;
    try {
      const result = await api.deleteCategory(id);
      alert(`Category deleted. ${result.affected_posts ?? 0} posts uncategorized.`);
      fetchCategories();
    } catch (e: any) {
      alert(e.message);
    }
  };

  return (
    <AdminShell>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Categories</h1>
          <p className="text-sm text-gray-500 mt-1">Manage content categories</p>
        </div>
        <button onClick={() => setShowCreate(!showCreate)} className="btn-primary text-sm flex items-center gap-1">
          <Plus className="w-4 h-4" /> New Category
        </button>
      </div>

      {showCreate && (
        <form onSubmit={handleCreate} className="card p-5 mb-4 space-y-3">
          <h3 className="font-semibold text-gray-900">Create Category</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <input className="input" placeholder="Slug (e.g. tech)" value={newCat.slug} onChange={(e) => setNewCat({ ...newCat, slug: e.target.value })} required />
            <input className="input" placeholder="Display Name" value={newCat.name} onChange={(e) => setNewCat({ ...newCat, name: e.target.value })} required />
          </div>
          <input className="input" placeholder="Description (optional)" value={newCat.description} onChange={(e) => setNewCat({ ...newCat, description: e.target.value })} />
          <label className="flex items-center gap-2 text-sm text-gray-600">
            <input type="checkbox" checked={newCat.is_sensitive} onChange={(e) => setNewCat({ ...newCat, is_sensitive: e.target.checked })} className="rounded" />
            Sensitive content (opt-in only)
          </label>
          <div className="flex gap-2">
            <button type="button" onClick={() => setShowCreate(false)} className="btn-secondary text-sm">Cancel</button>
            <button type="submit" className="btn-primary text-sm">Create</button>
          </div>
        </form>
      )}

      {loading ? (
        <div className="card p-8 animate-pulse"><div className="h-40 bg-warm-300 rounded" /></div>
      ) : categories.length === 0 ? (
        <div className="card p-12 text-center">
          <FolderTree className="w-12 h-12 text-gray-300 mx-auto mb-3" />
          <p className="text-gray-500">No categories yet</p>
        </div>
      ) : (
        <div className="card overflow-hidden">
          <table className="w-full">
            <thead className="bg-warm-200">
              <tr>
                <th className="table-header">Slug</th>
                <th className="table-header">Name</th>
                <th className="table-header">Description</th>
                <th className="table-header">Sensitive</th>
                <th className="table-header">Created</th>
                <th className="table-header">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-warm-300">
              {categories.map((cat) => (
                <tr key={cat.id} className="hover:bg-warm-50">
                  <td className="table-cell font-mono text-xs">{cat.slug}</td>
                  <td className="table-cell">
                    {editingId === cat.id ? (
                      <input className="input text-sm py-1" value={editData.name} onChange={(e) => setEditData({ ...editData, name: e.target.value })} />
                    ) : (
                      <span className="font-medium text-gray-900">{cat.name}</span>
                    )}
                  </td>
                  <td className="table-cell max-w-xs">
                    {editingId === cat.id ? (
                      <input className="input text-sm py-1" value={editData.description} onChange={(e) => setEditData({ ...editData, description: e.target.value })} />
                    ) : (
                      <span className="text-sm text-gray-500">{cat.description || '—'}</span>
                    )}
                  </td>
                  <td className="table-cell">
                    {editingId === cat.id ? (
                      <input type="checkbox" checked={editData.is_sensitive} onChange={(e) => setEditData({ ...editData, is_sensitive: e.target.checked })} />
                    ) : (
                      <span className={`badge ${cat.is_sensitive ? 'bg-red-100 text-red-700' : 'bg-green-100 text-green-700'}`}>
                        {cat.is_sensitive ? 'Yes' : 'No'}
                      </span>
                    )}
                  </td>
                  <td className="table-cell text-xs text-gray-500">{formatDate(cat.created_at)}</td>
                  <td className="table-cell">
                    {editingId === cat.id ? (
                      <div className="flex gap-1">
                        <button onClick={() => handleUpdate(cat.id)} className="p-1.5 bg-green-50 text-green-700 rounded hover:bg-green-100"><Save className="w-4 h-4" /></button>
                        <button onClick={() => setEditingId(null)} className="text-xs text-gray-500 hover:text-gray-700 px-2">Cancel</button>
                      </div>
                    ) : (
                      <div className="flex items-center gap-2">
                        <button
                          onClick={() => { setEditingId(cat.id); setEditData({ name: cat.name, description: cat.description || '', is_sensitive: cat.is_sensitive }); }}
                          className="text-brand-500 hover:text-brand-700 text-xs font-medium"
                          type="button"
                        >
                          Edit
                        </button>
                        <button
                          onClick={() => handleDelete(cat.id, cat.name)}
                          className="text-red-500 hover:text-red-700 p-1"
                          title="Delete category"
                          type="button"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      </div>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </AdminShell>
  );
}
