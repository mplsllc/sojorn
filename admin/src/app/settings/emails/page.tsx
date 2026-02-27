// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import AdminOnlyGuard from '@/components/AdminOnlyGuard';
import { api } from '@/lib/api';
import { useEffect, useState } from 'react';
import { Mail, Send, ChevronLeft, Save, Eye, EyeOff, ArrowLeft } from 'lucide-react';
import Link from 'next/link';

interface EmailTemplate {
  id: string;
  slug: string;
  name: string;
  description: string;
  subject: string;
  title: string;
  header: string;
  content: string;
  button_text: string;
  button_url: string;
  button_color: string;
  footer: string;
  text_body: string;
  enabled: boolean;
  updated_at: string;
  created_at: string;
}

function TemplateCard({ template, onSelect }: { template: EmailTemplate; onSelect: () => void }) {
  return (
    <button
      onClick={onSelect}
      className="card p-5 text-left hover:ring-2 hover:ring-brand-300 transition-all w-full"
    >
      <div className="flex items-start justify-between">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <Mail className="w-4 h-4 text-brand-500 flex-shrink-0" />
            <h3 className="font-semibold text-gray-900 truncate">{template.name}</h3>
          </div>
          <p className="text-xs text-gray-500 mb-2 line-clamp-2">{template.description}</p>
          <p className="text-xs font-mono text-gray-400 truncate">Subject: {template.subject}</p>
        </div>
        <div className="flex-shrink-0 ml-3">
          <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${template.enabled ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-500'}`}>
            {template.enabled ? 'Active' : 'Disabled'}
          </span>
        </div>
      </div>
      <p className="text-xs text-gray-400 mt-2">
        Last updated: {new Date(template.updated_at).toLocaleDateString()}
      </p>
    </button>
  );
}

function TemplateEditor({ template, onBack, onSaved }: { template: EmailTemplate; onBack: () => void; onSaved: () => void }) {
  const [form, setForm] = useState({ ...template });
  const [saving, setSaving] = useState(false);
  const [testEmail, setTestEmail] = useState('');
  const [sending, setSending] = useState(false);
  const [message, setMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);
  const [showPreview, setShowPreview] = useState(false);

  const handleSave = async () => {
    setSaving(true);
    setMessage(null);
    try {
      await api.updateEmailTemplate(template.id, {
        subject: form.subject,
        title: form.title,
        header: form.header,
        content: form.content,
        button_text: form.button_text,
        button_url: form.button_url,
        button_color: form.button_color,
        footer: form.footer,
        text_body: form.text_body,
        enabled: form.enabled,
      });
      setMessage({ type: 'success', text: 'Template saved successfully' });
      onSaved();
    } catch (err: any) {
      setMessage({ type: 'error', text: err.message || 'Failed to save' });
    } finally {
      setSaving(false);
    }
  };

  const handleSendTest = async () => {
    if (!testEmail) return;
    setSending(true);
    setMessage(null);
    try {
      await api.sendTestEmail(template.id, testEmail);
      setMessage({ type: 'success', text: `Test email sent to ${testEmail}` });
    } catch (err: any) {
      setMessage({ type: 'error', text: err.message || 'Failed to send test email' });
    } finally {
      setSending(false);
    }
  };

  return (
    <div>
      <button onClick={onBack} className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-900 mb-4 transition-colors">
        <ArrowLeft className="w-4 h-4" /> Back to templates
      </button>

      <div className="flex items-center justify-between mb-6">
        <div>
          <h2 className="text-xl font-bold text-gray-900">{template.name}</h2>
          <p className="text-sm text-gray-500">{template.description}</p>
          <p className="text-xs font-mono text-gray-400 mt-1">slug: {template.slug}</p>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={() => setShowPreview(!showPreview)}
            className="btn-secondary text-sm flex items-center gap-1"
          >
            {showPreview ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
            {showPreview ? 'Hide Preview' : 'Preview'}
          </button>
          <button
            onClick={handleSave}
            disabled={saving}
            className="btn-primary text-sm flex items-center gap-1"
          >
            <Save className="w-4 h-4" />
            {saving ? 'Saving...' : 'Save Changes'}
          </button>
        </div>
      </div>

      {message && (
        <div className={`mb-4 p-3 rounded-lg text-sm ${message.type === 'success' ? 'bg-green-50 text-green-700 border border-green-200' : 'bg-red-50 text-red-700 border border-red-200'}`}>
          {message.text}
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Editor */}
        <div className="space-y-4">
          {/* Enabled toggle */}
          <div className="card p-4">
            <label className="flex items-center gap-3 cursor-pointer">
              <input
                type="checkbox"
                checked={form.enabled}
                onChange={(e) => setForm({ ...form, enabled: e.target.checked })}
                className="w-4 h-4 rounded border-gray-300 text-brand-600 focus:ring-brand-500"
              />
              <span className="text-sm font-medium text-gray-700">Email enabled</span>
            </label>
          </div>

          {/* Subject */}
          <div className="card p-4">
            <label className="block text-sm font-medium text-gray-700 mb-1">Subject Line</label>
            <input
              className="input"
              value={form.subject}
              onChange={(e) => setForm({ ...form, subject: e.target.value })}
            />
            <p className="text-xs text-gray-400 mt-1">Supports placeholders: {'{{name}}, {{reason}}, {{content_type}}, etc.'}</p>
          </div>

          {/* Title & Header */}
          <div className="card p-4 space-y-3">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Email Title</label>
              <input
                className="input"
                value={form.title}
                onChange={(e) => setForm({ ...form, title: e.target.value })}
              />
              <p className="text-xs text-gray-400 mt-1">Shown in the colored header banner</p>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Header Text</label>
              <input
                className="input"
                value={form.header}
                onChange={(e) => setForm({ ...form, header: e.target.value })}
              />
              <p className="text-xs text-gray-400 mt-1">Large heading inside the email body</p>
            </div>
          </div>

          {/* Content (HTML) */}
          <div className="card p-4">
            <label className="block text-sm font-medium text-gray-700 mb-1">Content (HTML)</label>
            <textarea
              className="input font-mono text-xs"
              rows={10}
              value={form.content}
              onChange={(e) => setForm({ ...form, content: e.target.value })}
            />
            <p className="text-xs text-gray-400 mt-1">HTML content for the email body. Use {'{{name}}, {{reason}}, {{verify_url}}'}, etc.</p>
          </div>

          {/* Button */}
          <div className="card p-4 space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Button Text</label>
                <input
                  className="input"
                  value={form.button_text}
                  onChange={(e) => setForm({ ...form, button_text: e.target.value })}
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Button Color</label>
                <div className="flex items-center gap-2">
                  <input
                    type="color"
                    value={form.button_color}
                    onChange={(e) => setForm({ ...form, button_color: e.target.value })}
                    className="w-10 h-10 rounded border border-gray-300 cursor-pointer"
                  />
                  <input
                    className="input flex-1"
                    value={form.button_color}
                    onChange={(e) => setForm({ ...form, button_color: e.target.value })}
                  />
                </div>
              </div>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Button URL</label>
              <input
                className="input"
                value={form.button_url}
                onChange={(e) => setForm({ ...form, button_url: e.target.value })}
              />
            </div>
          </div>

          {/* Footer */}
          <div className="card p-4">
            <label className="block text-sm font-medium text-gray-700 mb-1">Footer (HTML, optional)</label>
            <textarea
              className="input font-mono text-xs"
              rows={3}
              value={form.footer}
              onChange={(e) => setForm({ ...form, footer: e.target.value })}
            />
          </div>

          {/* Plain text fallback */}
          <div className="card p-4">
            <label className="block text-sm font-medium text-gray-700 mb-1">Plain Text Fallback</label>
            <textarea
              className="input font-mono text-xs"
              rows={4}
              value={form.text_body}
              onChange={(e) => setForm({ ...form, text_body: e.target.value })}
            />
          </div>

          {/* Send Test */}
          <div className="card p-4">
            <label className="block text-sm font-medium text-gray-700 mb-2">Send Test Email</label>
            <div className="flex gap-2">
              <input
                className="input flex-1"
                type="email"
                placeholder="test@example.com"
                value={testEmail}
                onChange={(e) => setTestEmail(e.target.value)}
              />
              <button
                onClick={handleSendTest}
                disabled={sending || !testEmail}
                className="btn-primary text-sm flex items-center gap-1 whitespace-nowrap"
              >
                <Send className="w-4 h-4" />
                {sending ? 'Sending...' : 'Send Test'}
              </button>
            </div>
            <p className="text-xs text-gray-400 mt-1">Sends the saved version with sample placeholder data</p>
          </div>
        </div>

        {/* Preview */}
        {showPreview && (
          <div className="card p-0 overflow-hidden sticky top-6 self-start">
            <div className="bg-gray-100 px-4 py-2 border-b border-gray-200">
              <p className="text-xs font-medium text-gray-500">Email Preview</p>
            </div>
            <div className="p-4">
              <div className="mb-3 pb-3 border-b border-gray-100">
                <p className="text-xs text-gray-400">Subject</p>
                <p className="text-sm font-medium text-gray-900">{form.subject}</p>
              </div>
              <div
                className="bg-white rounded-lg overflow-hidden border border-gray-200"
                style={{ maxHeight: '600px', overflowY: 'auto' }}
              >
                {/* Simulated email header */}
                <div className="text-center p-8" style={{ backgroundColor: '#4338CA' }}>
                  <img src="https://mp.ls/img/sojornlogo.png" alt="Sojorn" className="w-16 h-16 rounded-2xl mx-auto mb-3" />
                  <p className="text-white text-xs font-semibold tracking-wider uppercase">{form.title}</p>
                </div>
                {/* Content */}
                <div className="p-6">
                  <h2 className="text-xl font-bold text-gray-900 mb-4 text-center">{form.header}</h2>
                  <div
                    className="text-sm text-gray-600 leading-relaxed mb-6 [&_p]:mb-3 [&_ul]:list-disc [&_ul]:pl-5 [&_li]:mb-1 [&_a]:text-indigo-600 [&_a]:underline"
                    dangerouslySetInnerHTML={{ __html: form.content }}
                  />
                  {form.button_text && (
                    <div className="text-center mb-4">
                      <span
                        className="inline-block px-8 py-3 text-white font-semibold rounded-xl text-sm"
                        style={{ backgroundColor: form.button_color }}
                      >
                        {form.button_text}
                      </span>
                    </div>
                  )}
                  {form.footer && (
                    <div
                      className="text-xs text-gray-400 [&_p]:mb-2"
                      dangerouslySetInnerHTML={{ __html: form.footer }}
                    />
                  )}
                </div>
                {/* Footer */}
                <div className="bg-gray-50 border-t border-gray-200 p-4 text-center">
                  <p className="text-xs text-gray-400">&copy; 2026 Sojorn by MPLS LLC. All rights reserved.</p>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

export default function EmailSettingsPage() {
  const [templates, setTemplates] = useState<EmailTemplate[]>([]);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<EmailTemplate | null>(null);

  const loadTemplates = () => {
    api.listEmailTemplates()
      .then((data) => setTemplates(data.templates || []))
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => { loadTemplates(); }, []);

  const handleSelect = (t: EmailTemplate) => {
    api.getEmailTemplate(t.id)
      .then((full) => setSelected(full))
      .catch(() => setSelected(t));
  };

  return (
    <AdminOnlyGuard>
    <AdminShell>
      {selected ? (
        <TemplateEditor
          template={selected}
          onBack={() => { setSelected(null); loadTemplates(); }}
          onSaved={loadTemplates}
        />
      ) : (
        <>
          <div className="mb-6">
            <div className="flex items-center gap-2 mb-1">
              <Link href="/settings" className="text-gray-400 hover:text-gray-600 transition-colors">
                <ChevronLeft className="w-5 h-5" />
              </Link>
              <h1 className="text-2xl font-bold text-gray-900">Email Templates</h1>
            </div>
            <p className="text-sm text-gray-500 mt-1">
              Manage the email templates sent for different app operations. Edit content, toggle emails on/off, and send test emails.
            </p>
          </div>

          {loading ? (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {[...Array(6)].map((_, i) => (
                <div key={i} className="card p-5 animate-pulse">
                  <div className="h-4 bg-warm-300 rounded w-32 mb-3" />
                  <div className="h-3 bg-warm-300 rounded w-48 mb-2" />
                  <div className="h-3 bg-warm-300 rounded w-40" />
                </div>
              ))}
            </div>
          ) : templates.length === 0 ? (
            <div className="card p-8 text-center text-gray-500">
              <Mail className="w-12 h-12 mx-auto mb-3 text-gray-300" />
              <p>No email templates found. Run the database migration to seed default templates.</p>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {templates.map((t) => (
                <TemplateCard key={t.id} template={t} onSelect={() => handleSelect(t)} />
              ))}
            </div>
          )}
        </>
      )}
    </AdminShell>
    </AdminOnlyGuard>
  );
}
