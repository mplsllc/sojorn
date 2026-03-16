// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8080';

const TOKEN_KEY = 'sojorn_token';
const REFRESH_KEY = 'sojorn_refresh_token';

function getToken(): string | null {
  if (typeof window === 'undefined') return null;
  return localStorage.getItem(TOKEN_KEY);
}

function setTokens(access: string, refresh?: string) {
  if (typeof window === 'undefined') return;
  localStorage.setItem(TOKEN_KEY, access);
  if (refresh) localStorage.setItem(REFRESH_KEY, refresh);
}

function clearTokens() {
  if (typeof window === 'undefined') return;
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(REFRESH_KEY);
}

function getRefreshToken(): string | null {
  if (typeof window === 'undefined') return null;
  return localStorage.getItem(REFRESH_KEY);
}

class ApiClient {
  private refreshPromise: Promise<boolean> | null = null;

  private async request<T>(path: string, options: RequestInit = {}): Promise<T> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      ...(options.headers as Record<string, string>),
    };

    const token = getToken();
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }

    const res = await fetch(`${API_BASE}${path}`, {
      ...options,
      headers,
      credentials: 'include',
    });

    if (res.status === 401) {
      const refreshed = await this.tryRefreshToken();
      if (refreshed) {
        const retryHeaders: Record<string, string> = {
          ...headers,
          Authorization: `Bearer ${getToken()}`,
        };
        const retry = await fetch(`${API_BASE}${path}`, {
          ...options,
          headers: retryHeaders,
          credentials: 'include',
        });
        if (retry.ok) {
          return retry.json();
        }
      }
      clearTokens();
      if (typeof window !== 'undefined' && !window.location.pathname.startsWith('/login')) {
        window.location.href = '/login';
      }
      throw new Error('Unauthorized');
    }

    if (!res.ok) {
      const body = await res.json().catch(() => ({ error: res.statusText }));
      throw new Error(body.error || `Request failed: ${res.status}`);
    }

    if (res.status === 204) {
      return {} as T;
    }

    return res.json();
  }

  private async tryRefreshToken(): Promise<boolean> {
    const refresh = getRefreshToken();
    if (!refresh) return false;

    if (this.refreshPromise) return this.refreshPromise;

    this.refreshPromise = (async () => {
      try {
        const res = await fetch(`${API_BASE}/api/v1/auth/refresh`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ refresh_token: refresh }),
          credentials: 'include',
        });
        if (!res.ok) return false;
        const data = await res.json();
        setTokens(data.token, data.refresh_token);
        return true;
      } catch {
        return false;
      } finally {
        this.refreshPromise = null;
      }
    })();

    return this.refreshPromise;
  }

  // ── Auth ──────────────────────────────────────────────────────────────

  async register(data: { email: string; password: string; handle: string; display_name?: string; invite_token?: string }) {
    const result = await this.request<{ user: any; token: string; refresh_token: string }>(
      '/api/v1/auth/register',
      { method: 'POST', body: JSON.stringify(data) },
    );
    setTokens(result.token, result.refresh_token);
    return result;
  }

  async login(email: string, password: string, mfa?: { mfa_token: string; mfa_code: string }) {
    const result = await this.request<{ user: any; token: string; refresh_token: string; mfa_required?: boolean; mfa_token?: string }>(
      '/api/v1/auth/login',
      { method: 'POST', body: JSON.stringify({ email, password, ...mfa }) },
    );
    if (!result.mfa_required) {
      setTokens(result.token, result.refresh_token);
    }
    return result;
  }

  async refreshToken() {
    const refreshed = await this.tryRefreshToken();
    if (!refreshed) throw new Error('Refresh failed');
    return { token: getToken() };
  }

  async logout() {
    await fetch(`${API_BASE}/api/v1/auth/logout`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(getToken() ? { Authorization: `Bearer ${getToken()}` } : {}),
      },
      credentials: 'include',
    }).catch(() => {});
    clearTokens();
  }

  // ── Profile ───────────────────────────────────────────────────────────

  async getProfile() {
    return this.request<any>('/api/v1/me');
  }

  async updateProfile(data: { display_name?: string; bio?: string; avatar_url?: string; header_url?: string; location?: string; website?: string }) {
    return this.request<any>('/api/v1/me', {
      method: 'PATCH',
      body: JSON.stringify(data),
    });
  }

  async getProfileByHandle(handle: string, params: { tab?: string; cursor?: string; limit?: number } = {}) {
    const qs = new URLSearchParams();
    if (params.tab) qs.set('tab', params.tab);
    if (params.cursor) qs.set('cursor', params.cursor);
    if (params.limit) qs.set('limit', String(params.limit));
    const query = qs.toString();
    return this.request<any>(`/api/v1/users/${encodeURIComponent(handle)}${query ? `?${query}` : ''}`);
  }

  // ── Posts ─────────────────────────────────────────────────────────────

  async createPost(data: {
    body?: string;
    content?: string;
    media_urls?: string[];
    visibility?: string;
    reply_to?: string;
    parent_id?: string;
    quote_of?: string;
    category_id?: string;
    tags?: string[];
    is_nsfw?: boolean;
    poll?: { options: string[]; expires_in: number };
  }) {
    const payload = {
      ...data,
      body: data.body ?? data.content,
      reply_to: data.reply_to ?? data.parent_id,
    };
    delete payload.content;
    delete payload.parent_id;
    return this.request<any>('/api/v1/posts', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  }

  async getPost(id: string) {
    return this.request<any>(`/api/v1/posts/${id}`);
  }

  async getFeed(params: { cursor?: string; limit?: number } = {}) {
    const qs = new URLSearchParams();
    if (params.cursor) qs.set('cursor', params.cursor);
    if (params.limit) qs.set('limit', String(params.limit));
    return this.request<any>(`/api/v1/feed?${qs}`);
  }

  async getSojornFeed(params: { cursor?: string; limit?: number } = {}) {
    const qs = new URLSearchParams();
    if (params.cursor) qs.set('cursor', params.cursor);
    if (params.limit) qs.set('limit', String(params.limit));
    return this.request<any>(`/api/v1/feed/sojorn?${qs}`);
  }

  async likePost(id: string) {
    return this.request<any>(`/api/v1/posts/${id}/like`, { method: 'POST' });
  }

  async unlikePost(id: string) {
    return this.request<any>(`/api/v1/posts/${id}/like`, { method: 'DELETE' });
  }

  async savePost(id: string) {
    return this.request<any>(`/api/v1/posts/${id}/save`, { method: 'POST' });
  }

  async createComment(postId: string, data: { body: string; media_urls?: string[] }) {
    return this.request<any>(`/api/v1/posts/${postId}/comments`, {
      method: 'POST',
      body: JSON.stringify(data),
    });
  }

  async getPostEdits(postId: string) {
    return this.request<any>(`/api/v1/posts/${postId}/edits`);
  }

  // ── Users / Social ────────────────────────────────────────────────────

  async follow(userId: string) {
    return this.request<any>(`/api/v1/users/${userId}/follow`, { method: 'POST' });
  }

  async unfollow(userId: string) {
    return this.request<any>(`/api/v1/users/${userId}/unfollow`, { method: 'POST' });
  }

  async block(userId: string) {
    return this.request<any>(`/api/v1/users/${userId}/block`, { method: 'POST' });
  }

  async getFollowers(userId: string, params: { cursor?: string; limit?: number } = {}) {
    const qs = new URLSearchParams();
    if (params.cursor) qs.set('cursor', params.cursor);
    if (params.limit) qs.set('limit', String(params.limit));
    return this.request<any>(`/api/v1/users/${userId}/followers?${qs}`);
  }

  async getFollowing(userId: string, params: { cursor?: string; limit?: number } = {}) {
    const qs = new URLSearchParams();
    if (params.cursor) qs.set('cursor', params.cursor);
    if (params.limit) qs.set('limit', String(params.limit));
    return this.request<any>(`/api/v1/users/${userId}/following?${qs}`);
  }

  async getSuggestedUsers(limit = 10) {
    return this.request<any>(`/api/v1/users/suggested?limit=${limit}`);
  }

  // ── Search & Discovery ────────────────────────────────────────────────

  async search(query: string, params: { type?: string; cursor?: string; limit?: number } = {}) {
    const qs = new URLSearchParams();
    qs.set('q', query);
    if (params.type) qs.set('type', params.type);
    if (params.cursor) qs.set('cursor', params.cursor);
    if (params.limit) qs.set('limit', String(params.limit));
    return this.request<any>(`/api/v1/search?${qs}`);
  }

  async getDiscover(params: { cursor?: string; limit?: number; category?: string } = {}) {
    const qs = new URLSearchParams();
    if (params.cursor) qs.set('cursor', params.cursor);
    if (params.limit) qs.set('limit', String(params.limit));
    if (params.category) qs.set('category', params.category);
    return this.request<any>(`/api/v1/discover?${qs}`);
  }

  async getTrendingHashtags(limit = 20) {
    return this.request<any>(`/api/v1/trending/hashtags?limit=${limit}`);
  }

  // ── Instance ──────────────────────────────────────────────────────────

  async getInstance() {
    return this.request<any>('/api/v1/instance');
  }

  async getAbout() {
    return this.request<any>('/api/v1/about');
  }

  async getVersion() {
    return this.request<any>('/api/v1/version');
  }

  // ── Notifications ─────────────────────────────────────────────────────

  async getNotifications(params: { cursor?: string; limit?: number; type?: string } = {}) {
    const qs = new URLSearchParams();
    if (params.cursor) qs.set('cursor', params.cursor);
    if (params.limit) qs.set('limit', String(params.limit));
    if (params.type) qs.set('type', params.type);
    return this.request<any>(`/api/v1/notifications?${qs}`);
  }

  async getUnreadCount() {
    return this.request<{ count: number }>('/api/v1/notifications/unread');
  }

  async markAsRead(ids: string[]) {
    return this.request<any>('/api/v1/notifications/read', {
      method: 'POST',
      body: JSON.stringify({ ids }),
    });
  }

  async markNotificationsRead() {
    return this.request<any>('/api/v1/notifications/read', {
      method: 'POST',
      body: JSON.stringify({ all: true }),
    });
  }

  // ── Chat ──────────────────────────────────────────────────────────────

  async getConversations(params: { cursor?: string; limit?: number } = {}) {
    const qs = new URLSearchParams();
    if (params.cursor) qs.set('cursor', params.cursor);
    if (params.limit) qs.set('limit', String(params.limit));
    return this.request<any>(`/api/v1/chat/conversations?${qs}`);
  }

  async getMessages(conversationId: string, params: { cursor?: string; limit?: number } = {}) {
    const qs = new URLSearchParams();
    if (params.cursor) qs.set('cursor', params.cursor);
    if (params.limit) qs.set('limit', String(params.limit));
    return this.request<any>(`/api/v1/chat/conversations/${conversationId}/messages?${qs}`);
  }

  async sendMessage(conversationId: string, data: { body: string; media_urls?: string[] }) {
    return this.request<any>(`/api/v1/chat/conversations/${conversationId}/messages`, {
      method: 'POST',
      body: JSON.stringify(data),
    });
  }

  // ── Settings ──────────────────────────────────────────────────────────

  async getPrivacySettings() {
    return this.request<any>('/api/v1/settings/privacy');
  }

  async updatePrivacySettings(data: {
    is_private?: boolean;
    show_online_status?: boolean;
    allow_dms_from?: string;
    hide_from_search?: boolean;
    hide_followers_count?: boolean;
    hide_following_count?: boolean;
  }) {
    return this.request<any>('/api/v1/settings/privacy', {
      method: 'PATCH',
      body: JSON.stringify(data),
    });
  }

  // ── Bookmarks ────────────────────────────────────────────────────────

  async bookmark(id: string) {
    return this.request<any>(`/api/v1/posts/${id}/save`, { method: 'POST' });
  }

  async unbookmark(id: string) {
    return this.request<any>(`/api/v1/posts/${id}/save`, { method: 'DELETE' });
  }

  // ── Reposts ─────────────────────────────────────────────────────────

  async repost(id: string) {
    return this.request<any>(`/api/v1/posts/${id}/repost`, { method: 'POST' });
  }

  async unrepost(id: string) {
    return this.request<any>(`/api/v1/posts/${id}/repost`, { method: 'DELETE' });
  }

  // ── Follow aliases ──────────────────────────────────────────────────

  async followUser(userId: string) {
    return this.follow(userId);
  }

  async unfollowUser(userId: string) {
    return this.unfollow(userId);
  }

  // ── Settings ────────────────────────────────────────────────────────

  async getSettings(category?: string) {
    const path = category ? `/api/v1/settings/${category}` : '/api/v1/settings';
    return this.request<any>(path);
  }

  async updateSettings(categoryOrData: string | Record<string, any>, data?: Record<string, any>) {
    if (typeof categoryOrData === 'string') {
      return this.request<any>(`/api/v1/settings/${categoryOrData}`, {
        method: 'PATCH',
        body: JSON.stringify(data),
      });
    }
    return this.request<any>('/api/v1/settings', {
      method: 'PATCH',
      body: JSON.stringify(categoryOrData),
    });
  }

  async changePassword(currentOrData: string | { current_password: string; new_password: string }, newPassword?: string) {
    const data = typeof currentOrData === 'string'
      ? { current_password: currentOrData, new_password: newPassword! }
      : currentOrData;
    return this.request<any>('/api/v1/auth/password', {
      method: 'POST',
      body: JSON.stringify(data),
    });
  }

  // ── MFA ─────────────────────────────────────────────────────────────

  async setupMfa() {
    return this.request<any>('/api/v1/auth/mfa/setup', { method: 'POST' });
  }

  async confirmMfa(code: string) {
    return this.request<any>('/api/v1/auth/mfa/confirm', {
      method: 'POST',
      body: JSON.stringify({ code }),
    });
  }

  async disableMfa(code?: string) {
    return this.request<any>('/api/v1/auth/mfa/disable', {
      method: 'POST',
      body: JSON.stringify({ code }),
    });
  }

  // ── Account ─────────────────────────────────────────────────────────

  async deactivateAccount(password?: string) {
    return this.request<any>('/api/v1/account/deactivate', {
      method: 'POST',
      body: JSON.stringify(password ? { password } : {}),
    });
  }

  async deleteAccount(password?: string) {
    return this.request<any>('/api/v1/account/delete', {
      method: 'POST',
      body: JSON.stringify(password ? { password } : {}),
    });
  }

  async exportData() {
    return this.request<any>('/api/v1/account/export', { method: 'POST' });
  }

  // ── Upload ────────────────────────────────────────────────────────────

  async uploadAvatar(file: File) {
    return this.uploadMedia(file, 'avatar');
  }

  async uploadMedia(file: File, type = 'image') {
    const form = new FormData();
    form.append('media', file);
    form.append('type', type);

    const headers: Record<string, string> = {};
    const token = getToken();
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }

    const res = await fetch(`${API_BASE}/api/v1/upload`, {
      method: 'POST',
      body: form,
      headers,
      credentials: 'include',
    });

    if (!res.ok) {
      const err = await res.json().catch(() => ({ error: res.statusText }));
      throw new Error(err.error || 'Upload failed');
    }

    return res.json() as Promise<{ url: string; key?: string }>;
  }
}

export const api = new ApiClient();
export { getToken, setTokens, clearTokens, TOKEN_KEY, REFRESH_KEY };
