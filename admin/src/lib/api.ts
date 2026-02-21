const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'https://api.sojorn.net';

class ApiClient {
  private token: string | null = null;

  setToken(token: string | null) {
    this.token = token;
    if (token) {
      if (typeof window !== 'undefined') localStorage.setItem('admin_token', token);
    } else {
      if (typeof window !== 'undefined') localStorage.removeItem('admin_token');
    }
  }

  getToken(): string | null {
    if (this.token) return this.token;
    if (typeof window !== 'undefined') {
      this.token = localStorage.getItem('admin_token');
    }
    return this.token;
  }

  private async request<T>(path: string, options: RequestInit = {}): Promise<T> {
    const token = this.getToken();
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      ...(options.headers as Record<string, string>),
    };
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }

    const res = await fetch(`${API_BASE}${path}`, {
      ...options,
      headers,
    });

    if (res.status === 401) {
      this.setToken(null);
      if (typeof window !== 'undefined') {
        window.location.href = '/login';
      }
      throw new Error('Unauthorized');
    }

    if (!res.ok) {
      const body = await res.json().catch(() => ({ error: res.statusText }));
      throw new Error(body.error || `Request failed: ${res.status}`);
    }

    return res.json();
  }

  // Auth
  async login(email: string, password: string, altchaToken?: string) {
    const body: Record<string, string> = { email, password };
    if (altchaToken) body.altcha_token = altchaToken;
    const data = await this.request<{ access_token: string; user: any }>('/api/v1/admin/login', {
      method: 'POST',
      body: JSON.stringify(body),
    });
    this.setToken(data.access_token);
    return data;
  }

  // Dashboard
  async getDashboardStats() {
    return this.request<any>('/api/v1/admin/dashboard');
  }

  async getGrowthStats(days = 30) {
    return this.request<any>(`/api/v1/admin/growth?days=${days}`);
  }

  // Users
  async listUsers(params: { limit?: number; offset?: number; search?: string; status?: string; role?: string } = {}) {
    const qs = new URLSearchParams();
    if (params.limit) qs.set('limit', String(params.limit));
    if (params.offset) qs.set('offset', String(params.offset));
    if (params.search) qs.set('search', params.search);
    if (params.status) qs.set('status', params.status);
    if (params.role) qs.set('role', params.role);
    return this.request<any>(`/api/v1/admin/users?${qs}`);
  }

  async getUser(id: string) {
    return this.request<any>(`/api/v1/admin/users/${id}`);
  }

  async updateUserStatus(id: string, status: string, reason: string) {
    return this.request<any>(`/api/v1/admin/users/${id}/status`, {
      method: 'PATCH',
      body: JSON.stringify({ status, reason }),
    });
  }

  async updateUserRole(id: string, role: string) {
    return this.request<any>(`/api/v1/admin/users/${id}/role`, {
      method: 'PATCH',
      body: JSON.stringify({ role }),
    });
  }

  async updateUserVerification(id: string, isOfficial: boolean, isVerified: boolean) {
    return this.request<any>(`/api/v1/admin/users/${id}/verification`, {
      method: 'PATCH',
      body: JSON.stringify({ is_official: isOfficial, is_verified: isVerified }),
    });
  }

  async resetUserStrikes(id: string) {
    return this.request<any>(`/api/v1/admin/users/${id}/reset-strikes`, { method: 'POST' });
  }

  async adminUpdateProfile(id: string, fields: Record<string, any>) {
    return this.request<any>(`/api/v1/admin/users/${id}/profile`, {
      method: 'PATCH',
      body: JSON.stringify(fields),
    });
  }

  async adminListFollows(id: string, relation: 'followers' | 'following', limit = 50) {
    return this.request<any>(`/api/v1/admin/users/${id}/follows?relation=${relation}&limit=${limit}`);
  }

  async adminManageFollow(id: string, action: 'add' | 'remove', userId: string, relation: 'follower' | 'following') {
    return this.request<any>(`/api/v1/admin/users/${id}/follows`, {
      method: 'POST',
      body: JSON.stringify({ action, user_id: userId, relation }),
    });
  }

  // Posts
  async listPosts(params: { limit?: number; offset?: number; search?: string; status?: string; author_id?: string } = {}) {
    const qs = new URLSearchParams();
    if (params.limit) qs.set('limit', String(params.limit));
    if (params.offset) qs.set('offset', String(params.offset));
    if (params.search) qs.set('search', params.search);
    if (params.status) qs.set('status', params.status);
    if (params.author_id) qs.set('author_id', params.author_id);
    return this.request<any>(`/api/v1/admin/posts?${qs}`);
  }

  async getPost(id: string) {
    return this.request<any>(`/api/v1/admin/posts/${id}`);
  }

  async updatePostStatus(id: string, status: string, reason?: string) {
    return this.request<any>(`/api/v1/admin/posts/${id}/status`, {
      method: 'PATCH',
      body: JSON.stringify({ status, reason }),
    });
  }

  async deletePost(id: string) {
    return this.request<any>(`/api/v1/admin/posts/${id}`, { method: 'DELETE' });
  }

  async bulkUpdatePosts(ids: string[], action: string, reason?: string) {
    return this.request<any>('/api/v1/admin/posts/bulk', {
      method: 'POST',
      body: JSON.stringify({ ids, action, reason }),
    });
  }

  async bulkUpdateUsers(ids: string[], action: string, reason?: string) {
    return this.request<any>('/api/v1/admin/users/bulk', {
      method: 'POST',
      body: JSON.stringify({ ids, action, reason }),
    });
  }

  // Moderation
  async getModerationQueue(params: { limit?: number; offset?: number; status?: string } = {}) {
    const qs = new URLSearchParams();
    if (params.limit) qs.set('limit', String(params.limit));
    if (params.offset) qs.set('offset', String(params.offset));
    if (params.status) qs.set('status', params.status || 'pending');
    return this.request<any>(`/api/v1/admin/moderation?${qs}`);
  }

  async reviewModerationFlag(id: string, action: string, reason?: string) {
    return this.request<any>(`/api/v1/admin/moderation/${id}/review`, {
      method: 'PATCH',
      body: JSON.stringify({ action, reason }),
    });
  }

  async bulkReviewModeration(ids: string[], action: string, reason?: string) {
    return this.request<any>('/api/v1/admin/moderation/bulk', {
      method: 'POST',
      body: JSON.stringify({ ids, action, reason }),
    });
  }

  // Appeals
  async listAppeals(params: { limit?: number; offset?: number; status?: string } = {}) {
    const qs = new URLSearchParams();
    if (params.limit) qs.set('limit', String(params.limit));
    if (params.offset) qs.set('offset', String(params.offset));
    if (params.status) qs.set('status', params.status || 'pending');
    return this.request<any>(`/api/v1/admin/appeals?${qs}`);
  }

  async reviewAppeal(id: string, decision: string, reviewDecision: string, restoreContent = false) {
    return this.request<any>(`/api/v1/admin/appeals/${id}/review`, {
      method: 'PATCH',
      body: JSON.stringify({ decision, review_decision: reviewDecision, restore_content: restoreContent }),
    });
  }

  // Reports
  async listReports(params: { limit?: number; offset?: number; status?: string } = {}) {
    const qs = new URLSearchParams();
    if (params.limit) qs.set('limit', String(params.limit));
    if (params.offset) qs.set('offset', String(params.offset));
    if (params.status) qs.set('status', params.status || 'pending');
    return this.request<any>(`/api/v1/admin/reports?${qs}`);
  }

  async updateReportStatus(id: string, status: string) {
    return this.request<any>(`/api/v1/admin/reports/${id}`, {
      method: 'PATCH',
      body: JSON.stringify({ status }),
    });
  }

  async bulkUpdateReports(ids: string[], action: string) {
    return this.request<any>('/api/v1/admin/reports/bulk', {
      method: 'POST',
      body: JSON.stringify({ ids, action }),
    });
  }

  // Capsule Reports
  async listCapsuleReports(params: { limit?: number; offset?: number; status?: string } = {}) {
    const qs = new URLSearchParams();
    if (params.limit) qs.set('limit', String(params.limit));
    if (params.offset) qs.set('offset', String(params.offset));
    if (params.status) qs.set('status', params.status);
    return this.request<any>(`/api/v1/admin/capsule-reports?${qs}`);
  }

  async updateCapsuleReportStatus(id: string, status: string) {
    return this.request<any>(`/api/v1/admin/capsule-reports/${id}`, {
      method: 'PATCH',
      body: JSON.stringify({ status }),
    });
  }

  // Algorithm
  async getAlgorithmConfig() {
    return this.request<any>('/api/v1/admin/algorithm');
  }

  async updateAlgorithmConfig(key: string, value: string) {
    return this.request<any>('/api/v1/admin/algorithm', {
      method: 'PUT',
      body: JSON.stringify({ key, value }),
    });
  }

  // Categories
  async listCategories() {
    return this.request<any>('/api/v1/admin/categories');
  }

  async createCategory(data: { slug: string; name: string; description?: string; is_sensitive?: boolean }) {
    return this.request<any>('/api/v1/admin/categories', {
      method: 'POST',
      body: JSON.stringify(data),
    });
  }

  async updateCategory(id: string, data: { name?: string; description?: string; is_sensitive?: boolean }) {
    return this.request<any>(`/api/v1/admin/categories/${id}`, {
      method: 'PATCH',
      body: JSON.stringify(data),
    });
  }

  // Neighborhoods
  async listNeighborhoods(params: {
    limit?: number;
    offset?: number;
    search?: string;
    zip?: string;
    sort?: 'name' | 'zip' | 'members' | 'created';
    order?: 'asc' | 'desc';
  } = {}) {
    const qs = new URLSearchParams();
    if (params.limit) qs.set('limit', String(params.limit));
    if (params.offset) qs.set('offset', String(params.offset));
    if (params.search) qs.set('search', params.search);
    if (params.zip) qs.set('zip', params.zip);
    if (params.sort) qs.set('sort', params.sort);
    if (params.order) qs.set('order', params.order);
    return this.request<any>(`/api/v1/admin/neighborhoods?${qs}`);
  }

  async setNeighborhoodAdmin(id: string, userId: string, action: 'assign' | 'remove') {
    return this.request<any>(`/api/v1/admin/neighborhoods/${id}/admins`, {
      method: 'POST',
      body: JSON.stringify({ user_id: userId, action }),
    });
  }

  async listNeighborhoodAdmins(id: string) {
    return this.request<any>(`/api/v1/admin/neighborhoods/${id}/admins`);
  }

  async listNeighborhoodBoardEntries(id: string, params: {
    limit?: number;
    offset?: number;
    search?: string;
    active?: 'true' | 'false';
  } = {}) {
    const qs = new URLSearchParams();
    if (params.limit) qs.set('limit', String(params.limit));
    if (params.offset) qs.set('offset', String(params.offset));
    if (params.search) qs.set('search', params.search);
    if (params.active) qs.set('active', params.active);
    return this.request<any>(`/api/v1/admin/neighborhoods/${id}/board?${qs}`);
  }

  async updateNeighborhoodBoardEntry(id: string, entryId: string, isActive: boolean) {
    return this.request<any>(`/api/v1/admin/neighborhoods/${id}/board/${entryId}`, {
      method: 'PATCH',
      body: JSON.stringify({ is_active: isActive }),
    });
  }

  async pinNeighborhoodBoardEntry(id: string, entryId: string, isPinned: boolean) {
    return this.request<any>(`/api/v1/admin/neighborhoods/${id}/board/${entryId}`, {
      method: 'PATCH',
      body: JSON.stringify({ is_pinned: isPinned }),
    });
  }

  // System
  async getSystemHealth() {
    return this.request<any>('/api/v1/admin/health');
  }

  async getAuditLog(params: { limit?: number; offset?: number } = {}) {
    const qs = new URLSearchParams();
    if (params.limit) qs.set('limit', String(params.limit));
    if (params.offset) qs.set('offset', String(params.offset));
    return this.request<any>(`/api/v1/admin/audit-log?${qs}`);
  }

  // R2 Storage
  async getStorageStats() {
    return this.request<any>('/api/v1/admin/storage/stats');
  }

  async listStorageObjects(params: { bucket?: string; prefix?: string; cursor?: string; limit?: number } = {}) {
    const qs = new URLSearchParams();
    if (params.bucket) qs.set('bucket', params.bucket);
    if (params.prefix) qs.set('prefix', params.prefix);
    if (params.cursor) qs.set('cursor', params.cursor);
    if (params.limit) qs.set('limit', String(params.limit));
    return this.request<any>(`/api/v1/admin/storage/objects?${qs}`);
  }

  async deleteStorageObject(bucket: string, key: string) {
    return this.request<any>('/api/v1/admin/storage/object', {
      method: 'DELETE',
      body: JSON.stringify({ bucket, key }),
    });
  }

  // Reserved Usernames
  async listReservedUsernames(params: { category?: string; search?: string; limit?: number; offset?: number } = {}) {
    const qs = new URLSearchParams();
    if (params.category) qs.set('category', params.category);
    if (params.search) qs.set('search', params.search);
    if (params.limit) qs.set('limit', String(params.limit));
    if (params.offset) qs.set('offset', String(params.offset));
    return this.request<any>(`/api/v1/admin/usernames/reserved?${qs}`);
  }

  async addReservedUsername(data: { username: string; category?: string; reason?: string }) {
    return this.request<any>('/api/v1/admin/usernames/reserved', {
      method: 'POST',
      body: JSON.stringify(data),
    });
  }

  async bulkAddReservedUsernames(data: { usernames: string[]; category?: string; reason?: string }) {
    return this.request<any>('/api/v1/admin/usernames/reserved/bulk', {
      method: 'POST',
      body: JSON.stringify(data),
    });
  }

  async removeReservedUsername(id: string) {
    return this.request<any>(`/api/v1/admin/usernames/reserved/${id}`, { method: 'DELETE' });
  }

  // Username Claim Requests
  async listClaimRequests(params: { status?: string; limit?: number; offset?: number } = {}) {
    const qs = new URLSearchParams();
    if (params.status) qs.set('status', params.status);
    if (params.limit) qs.set('limit', String(params.limit));
    if (params.offset) qs.set('offset', String(params.offset));
    return this.request<any>(`/api/v1/admin/usernames/claims?${qs}`);
  }

  async reviewClaimRequest(id: string, decision: string, notes?: string) {
    return this.request<any>(`/api/v1/admin/usernames/claims/${id}`, {
      method: 'PATCH',
      body: JSON.stringify({ decision, notes }),
    });
  }

  // AI Engines
  async getAIEngines() {
    return this.request<any>('/api/v1/admin/ai-engines');
  }

  // AI Moderation
  async listLocalModels() {
    return this.request<any>('/api/v1/admin/ai/models/local');
  }

  async getAIModerationConfigs() {
    return this.request<any>('/api/v1/admin/ai/config');
  }

  async setAIModerationConfig(data: { moderation_type: string; model_id: string; model_name: string; system_prompt: string; enabled: boolean; engines?: string[] }) {
    return this.request<any>('/api/v1/admin/ai/config', {
      method: 'PUT',
      body: JSON.stringify(data),
    });
  }

  async testAIModeration(data: { moderation_type: string; content?: string; image_url?: string; engine?: string }) {
    return this.request<any>('/api/v1/admin/ai/test', {
      method: 'POST',
      body: JSON.stringify(data),
    });
  }

  async uploadTestImage(file: File) {
    const formData = new FormData();
    formData.append('file', file);
    
    const token = this.getToken();
    const headers: Record<string, string> = {};
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }
    
    const response = await fetch(`${API_BASE}/api/v1/admin/upload-test-image`, {
      method: 'POST',
      body: formData,
      headers,
    });
    
    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Upload failed: ${response.status} - ${errorText}`);
    }
    
    return response.json();
  }

  // AI Moderation Audit Log
  async getAIModerationLog(params: { limit?: number; offset?: number; decision?: string; content_type?: string; search?: string; feedback?: string } = {}) {
    const qs = new URLSearchParams();
    if (params.limit) qs.set('limit', String(params.limit));
    if (params.offset) qs.set('offset', String(params.offset));
    if (params.decision) qs.set('decision', params.decision);
    if (params.content_type) qs.set('content_type', params.content_type);
    if (params.search) qs.set('search', params.search);
    if (params.feedback) qs.set('feedback', params.feedback);
    return this.request<any>(`/api/v1/admin/ai/moderation-log?${qs}`);
  }

  async submitAIModerationFeedback(id: string, correct: boolean, reason: string) {
    return this.request<any>(`/api/v1/admin/ai/moderation-log/${id}/feedback`, {
      method: 'POST',
      body: JSON.stringify({ correct, reason }),
    });
  }

  async exportAITrainingData() {
    return this.request<any>('/api/v1/admin/ai/training-data');
  }

  // Admin Content Tools
  async adminCreateUser(data: {
    email: string;
    password: string;
    handle: string;
    display_name: string;
    bio?: string;
    role?: string;
    verified?: boolean;
    official?: boolean;
    skip_email?: boolean;
  }) {
    return this.request<any>('/api/v1/admin/users/create', {
      method: 'POST',
      body: JSON.stringify(data),
    });
  }

  // Official Accounts
  async listOfficialProfiles() {
    return this.request<any>('/api/v1/admin/official-profiles');
  }

  async listOfficialAccounts() {
    return this.request<any>('/api/v1/admin/official-accounts');
  }

  async upsertOfficialAccount(data: any) {
    return this.request<any>('/api/v1/admin/official-accounts', {
      method: 'POST',
      body: JSON.stringify(data),
    });
  }

  async deleteOfficialAccount(id: string) {
    return this.request<any>(`/api/v1/admin/official-accounts/${id}`, { method: 'DELETE' });
  }

  async toggleOfficialAccount(id: string, enabled: boolean) {
    return this.request<any>(`/api/v1/admin/official-accounts/${id}/toggle`, {
      method: 'PATCH',
      body: JSON.stringify({ enabled }),
    });
  }

  async triggerOfficialPost(id: string, count?: number | 'all') {
    const q = count !== undefined ? `?count=${count}` : '';
    return this.request<any>(`/api/v1/admin/official-accounts/${id}/trigger${q}`, { method: 'POST' });
  }

  async previewOfficialPost(id: string) {
    return this.request<any>(`/api/v1/admin/official-accounts/${id}/preview`, { method: 'POST' });
  }

  async fetchNewsArticles(id: string) {
    return this.request<any>(`/api/v1/admin/official-accounts/${id}/articles`);
  }

  async getPostedArticles(id: string, limit = 50, status = 'posted') {
    return this.request<any>(`/api/v1/admin/official-accounts/${id}/posted?limit=${limit}&status=${status}`);
  }

  async skipArticle(articleId: string) {
    return this.request<any>(`/api/v1/admin/official-accounts/articles/${articleId}/skip`, { method: 'POST' });
  }

  async deleteArticle(articleId: string) {
    return this.request<any>(`/api/v1/admin/official-accounts/articles/${articleId}`, { method: 'DELETE' });
  }

  async postSpecificArticle(articleId: string) {
    return this.request<any>(`/api/v1/admin/official-accounts/articles/${articleId}/post`, { method: 'POST' });
  }

  async cleanupPendingArticles(configId: string, before: string, action: 'skip' | 'delete') {
    return this.request<any>(`/api/v1/admin/official-accounts/${configId}/articles/cleanup`, {
      method: 'POST',
      body: JSON.stringify({ before, action }),
    });
  }

  async adminImportContent(data: {
    author_id: string;
    content_type: string;
    items: Array<{
      body?: string;
      media_url?: string;
      thumbnail_url?: string;
      duration_ms?: number;
      tags?: string[];
      category_id?: string;
      is_nsfw?: boolean;
      nsfw_reason?: string;
      visibility?: string;
      beacon_type?: string;
      lat?: number;
      long?: number;
    }>;
  }) {
    return this.request<any>('/api/v1/admin/content/import', {
      method: 'POST',
      body: JSON.stringify(data),
    });
  }
  // Safe Domains
  async listSafeDomains(category?: string) {
    const params = category ? `?category=${category}` : '';
    return this.request<any>(`/api/v1/admin/safe-domains${params}`);
  }

  async upsertSafeDomain(data: { domain: string; category: string; is_approved: boolean; notes: string }) {
    return this.request<any>('/api/v1/admin/safe-domains', { method: 'POST', body: JSON.stringify(data) });
  }

  async deleteSafeDomain(id: string) {
    return this.request<any>(`/api/v1/admin/safe-domains/${id}`, { method: 'DELETE' });
  }

  async checkURLSafety(url: string) {
    return this.request<any>(`/api/v1/admin/safe-domains/check?url=${encodeURIComponent(url)}`);
  }

  // Email Templates
  async listEmailTemplates() {
    return this.request<any>('/api/v1/admin/email-templates');
  }

  async getEmailTemplate(id: string) {
    return this.request<any>(`/api/v1/admin/email-templates/${id}`);
  }

  async updateEmailTemplate(id: string, data: Record<string, any>) {
    return this.request<any>(`/api/v1/admin/email-templates/${id}`, {
      method: 'PATCH',
      body: JSON.stringify(data),
    });
  }

  async sendTestEmail(templateId: string, toEmail: string) {
    return this.request<any>('/api/v1/admin/email-templates/test', {
      method: 'POST',
      body: JSON.stringify({ template_id: templateId, to_email: toEmail }),
    });
  }

  // Groups admin
  async listGroups(params: { search?: string; limit?: number; offset?: number } = {}) {
    const qs = new URLSearchParams();
    if (params.search) qs.set('search', params.search);
    if (params.limit) qs.set('limit', String(params.limit));
    if (params.offset) qs.set('offset', String(params.offset));
    return this.request<any>(`/api/v1/admin/groups?${qs}`);
  }

  async deleteGroup(id: string) {
    return this.request<any>(`/api/v1/admin/groups/${id}`, { method: 'DELETE' });
  }

  async listGroupMembers(groupId: string) {
    return this.request<any>(`/api/v1/admin/groups/${groupId}/members`);
  }

  async removeGroupMember(groupId: string, userId: string) {
    return this.request<any>(`/api/v1/admin/groups/${groupId}/members/${userId}`, { method: 'DELETE' });
  }

  // Quip repair
  async getBrokenQuips(limit = 50) {
    return this.request<any>(`/api/v1/admin/quips/broken?limit=${limit}`);
  }

  async repairQuip(postId: string) {
    return this.request<any>(`/api/v1/admin/quips/${postId}/repair`, { method: 'POST' });
  }

  // Feed scores
  async getFeedScores(limit = 50) {
    return this.request<any>(`/api/v1/admin/feed-scores?limit=${limit}`);
  }

  // Waitlist
  async listWaitlist(params: { status?: string; limit?: number; offset?: number } = {}) {
    const qs = new URLSearchParams();
    if (params.status) qs.set('status', params.status);
    if (params.limit) qs.set('limit', String(params.limit));
    if (params.offset) qs.set('offset', String(params.offset));
    return this.request<any>(`/api/v1/admin/waitlist?${qs}`);
  }

  async updateWaitlist(id: string, data: { status?: string; notes?: string }) {
    return this.request<any>(`/api/v1/admin/waitlist/${id}`, {
      method: 'PATCH',
      body: JSON.stringify(data),
    });
  }

  async deleteWaitlist(id: string) {
    return this.request<any>(`/api/v1/admin/waitlist/${id}`, { method: 'DELETE' });
  }

  // Feed impression reset
  async resetFeedImpressions(userId: string) {
    return this.request<any>(`/api/v1/admin/users/${userId}/feed-impressions`, { method: 'DELETE' });
  }
}

export const api = new ApiClient();
