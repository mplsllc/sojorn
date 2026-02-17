'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { formatDate } from '@/lib/utils';
import { useEffect, useState } from 'react';
import { Search, Trash2, Users, RotateCcw } from 'lucide-react';

export default function GroupsPage() {
  const [groups, setGroups] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [offset, setOffset] = useState(0);
  const [selectedGroup, setSelectedGroup] = useState<any | null>(null);
  const [members, setMembers] = useState<any[]>([]);
  const [membersLoading, setMembersLoading] = useState(false);
  const limit = 50;

  const fetchGroups = () => {
    setLoading(true);
    api.listGroups({ search: search || undefined, limit, offset })
      .then((data) => setGroups(data.groups ?? []))
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchGroups(); }, [offset]);

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    setOffset(0);
    fetchGroups();
  };

  const openGroup = async (group: any) => {
    setSelectedGroup(group);
    setMembersLoading(true);
    try {
      const data = await api.listGroupMembers(group.id);
      setMembers(data.members ?? []);
    } catch {
      setMembers([]);
    } finally {
      setMembersLoading(false);
    }
  };

  const deactivateGroup = async (id: string) => {
    if (!confirm('Deactivate this group?')) return;
    try {
      await api.deleteGroup(id);
      setGroups((prev) => prev.filter((g) => g.id !== id));
      if (selectedGroup?.id === id) setSelectedGroup(null);
    } catch (e: any) {
      alert(e.message);
    }
  };

  const removeMember = async (groupId: string, userId: string) => {
    if (!confirm('Remove this member? Key rotation will be triggered.')) return;
    try {
      await api.removeGroupMember(groupId, userId);
      setMembers((prev) => prev.filter((m) => m.user_id !== userId));
    } catch (e: any) {
      alert(e.message);
    }
  };

  return (
    <AdminShell>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Groups & Capsules</h1>
          <p className="text-sm text-gray-500 mt-1">Manage community groups and E2EE capsules</p>
        </div>
      </div>

      <form onSubmit={handleSearch} className="mb-4 flex gap-2">
        <div className="relative flex-1 max-w-md">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 w-4 h-4" />
          <input
            className="pl-9 pr-4 py-2 border rounded-lg w-full text-sm"
            placeholder="Search groups..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <button type="submit" className="px-4 py-2 bg-navy-600 text-white rounded-lg text-sm font-medium bg-blue-700 hover:bg-blue-800">
          Search
        </button>
      </form>

      <div className="flex gap-6">
        {/* Groups list */}
        <div className="flex-1 bg-white rounded-xl border overflow-hidden">
          {loading ? (
            <div className="p-8 text-center text-gray-400">Loading…</div>
          ) : groups.length === 0 ? (
            <div className="p-8 text-center text-gray-400">No groups found</div>
          ) : (
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b">
                <tr>
                  <th className="px-4 py-3 text-left font-medium text-gray-600">Name</th>
                  <th className="px-4 py-3 text-left font-medium text-gray-600">Type</th>
                  <th className="px-4 py-3 text-center font-medium text-gray-600">Members</th>
                  <th className="px-4 py-3 text-center font-medium text-gray-600">Key v</th>
                  <th className="px-4 py-3 text-center font-medium text-gray-600">Rotation</th>
                  <th className="px-4 py-3 text-left font-medium text-gray-600">Created</th>
                  <th className="px-4 py-3" />
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {groups.map((g) => (
                  <tr
                    key={g.id}
                    className={`hover:bg-gray-50 cursor-pointer ${selectedGroup?.id === g.id ? 'bg-blue-50' : ''}`}
                    onClick={() => openGroup(g)}
                  >
                    <td className="px-4 py-3 font-medium text-gray-900">{g.name}</td>
                    <td className="px-4 py-3">
                      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${g.is_private ? 'bg-purple-100 text-purple-700' : 'bg-green-100 text-green-700'}`}>
                        {g.is_private ? 'Capsule' : 'Public'}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-center">{g.member_count}</td>
                    <td className="px-4 py-3 text-center text-gray-500">v{g.key_version}</td>
                    <td className="px-4 py-3 text-center">
                      {g.key_rotation_needed && (
                        <span className="px-2 py-0.5 rounded-full text-xs bg-amber-100 text-amber-700">Pending</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-gray-500">{formatDate(g.created_at)}</td>
                    <td className="px-4 py-3 text-right">
                      <button
                        onClick={(e) => { e.stopPropagation(); deactivateGroup(g.id); }}
                        className="text-red-500 hover:text-red-700 p-1"
                        title="Deactivate group"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
          <div className="px-4 py-3 border-t flex items-center gap-3">
            <button disabled={offset === 0} onClick={() => setOffset(Math.max(0, offset - limit))}
              className="text-sm px-3 py-1.5 rounded border disabled:opacity-40">Prev</button>
            <button disabled={groups.length < limit} onClick={() => setOffset(offset + limit)}
              className="text-sm px-3 py-1.5 rounded border disabled:opacity-40">Next</button>
          </div>
        </div>

        {/* Member panel */}
        {selectedGroup && (
          <div className="w-72 bg-white rounded-xl border overflow-hidden self-start">
            <div className="px-4 py-3 border-b bg-gray-50 flex items-center gap-2">
              <Users className="w-4 h-4 text-gray-500" />
              <span className="font-semibold text-sm text-gray-800">{selectedGroup.name}</span>
            </div>
            {membersLoading ? (
              <div className="p-6 text-center text-gray-400 text-sm">Loading members…</div>
            ) : members.length === 0 ? (
              <div className="p-6 text-center text-gray-400 text-sm">No members</div>
            ) : (
              <ul className="divide-y divide-gray-100 max-h-96 overflow-y-auto">
                {members.map((m) => (
                  <li key={m.user_id} className="px-4 py-2.5 flex items-center justify-between text-sm">
                    <div>
                      <p className="font-medium text-gray-800">{m.username || m.display_name}</p>
                      <p className="text-xs text-gray-400">{m.role}</p>
                    </div>
                    {m.role !== 'owner' && (
                      <button
                        onClick={() => removeMember(selectedGroup.id, m.user_id)}
                        className="text-red-400 hover:text-red-600 p-1"
                        title="Remove member"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    )}
                  </li>
                ))}
              </ul>
            )}
            {selectedGroup.key_rotation_needed && (
              <div className="px-4 py-3 border-t bg-amber-50">
                <div className="flex items-center gap-2 text-amber-700 text-xs">
                  <RotateCcw className="w-3.5 h-3.5" />
                  Key rotation pending — will auto-complete next time an admin opens this capsule.
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </AdminShell>
  );
}
