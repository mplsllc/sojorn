'use client';

import { useState, useEffect, FormEvent, useRef } from 'react';
import { useRouter } from 'next/navigation';
import Image from 'next/image';
import { api } from '@/lib/api';
import { useAuth } from '@/lib/auth';
import { Nav } from '@/components/Nav';
import { Button } from '@/components/Button';
import { LoadingSpinner } from '@/components/LoadingSpinner';
import {
  User,
  Shield,
  Bell,
  Key,
  Camera,
  Save,
  Download,
  AlertTriangle,
  Smartphone,
  Eye,
  EyeOff,
} from 'lucide-react';

type SettingsSection =
  | 'profile'
  | 'privacy'
  | 'notifications'
  | 'account'
  | 'mfa';

interface ProfileData {
  display_name: string;
  bio: string;
  avatar_url: string;
  header_url?: string;
}

interface PrivacySettings {
  profile_visibility: 'public' | 'followers' | 'private';
  dm_policy: 'everyone' | 'followers' | 'nobody';
  searchable: boolean;
}

interface NotificationSettings {
  likes: boolean;
  replies: boolean;
  follows: boolean;
  mentions: boolean;
  reposts: boolean;
  polls: boolean;
  email_digest: boolean;
}

interface MfaState {
  enabled: boolean;
  qr_code?: string;
  secret?: string;
  backup_codes?: string[];
}

const sections: { key: SettingsSection; label: string; icon: React.ElementType }[] = [
  { key: 'profile', label: 'Profile', icon: User },
  { key: 'privacy', label: 'Privacy', icon: Shield },
  { key: 'notifications', label: 'Notifications', icon: Bell },
  { key: 'account', label: 'Account', icon: Key },
  { key: 'mfa', label: 'Two-factor auth', icon: Smartphone },
];

export default function SettingsPage() {
  const { user, isLoading: authLoading, logout } = useAuth();
  const router = useRouter();

  const [activeSection, setActiveSection] = useState<SettingsSection>('profile');
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [message, setMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);

  // Profile state
  const [profile, setProfile] = useState<ProfileData>({
    display_name: '',
    bio: '',
    avatar_url: '',
  });
  const avatarInputRef = useRef<HTMLInputElement>(null);

  // Privacy state
  const [privacy, setPrivacy] = useState<PrivacySettings>({
    profile_visibility: 'public',
    dm_policy: 'everyone',
    searchable: true,
  });

  // Notification state
  const [notifications, setNotifications] = useState<NotificationSettings>({
    likes: true,
    replies: true,
    follows: true,
    mentions: true,
    reposts: true,
    polls: true,
    email_digest: false,
  });

  // Account state
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showPasswords, setShowPasswords] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [deleteConfirmText, setDeleteConfirmText] = useState('');

  // MFA state
  const [mfa, setMfa] = useState<MfaState>({ enabled: false });
  const [mfaCode, setMfaCode] = useState('');
  const [mfaSetupStep, setMfaSetupStep] = useState<'idle' | 'setup' | 'verify' | 'backup'>('idle');

  useEffect(() => {
    if (!authLoading && !user) {
      router.replace('/auth/login');
    }
  }, [user, authLoading, router]);

  useEffect(() => {
    if (!user) return;
    const loadSettings = async () => {
      try {
        const [profileData, privacyData, notifData, mfaData] = await Promise.all([
          api.getSettings('profile'),
          api.getSettings('privacy'),
          api.getSettings('notifications'),
          api.getSettings('mfa'),
        ]);
        if (profileData) setProfile(profileData);
        if (privacyData) setPrivacy(privacyData);
        if (notifData) setNotifications(notifData);
        if (mfaData) setMfa(mfaData);
      } catch {
        setMessage({ type: 'error', text: 'Failed to load settings.' });
      } finally {
        setIsLoading(false);
      }
    };
    loadSettings();
  }, [user]);

  const showMessage = (type: 'success' | 'error', text: string) => {
    setMessage({ type, text });
    setTimeout(() => setMessage(null), 4000);
  };

  const handleAvatarChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    try {
      const data = await api.uploadAvatar(file);
      setProfile((p) => ({ ...p, avatar_url: data.url }));
      showMessage('success', 'Avatar updated.');
    } catch {
      showMessage('error', 'Failed to upload avatar.');
    }
  };

  const saveProfile = async (e: FormEvent) => {
    e.preventDefault();
    setIsSaving(true);
    try {
      await api.updateSettings('profile', {
        display_name: profile.display_name,
        bio: profile.bio,
      });
      showMessage('success', 'Profile saved.');
    } catch {
      showMessage('error', 'Failed to save profile.');
    } finally {
      setIsSaving(false);
    }
  };

  const savePrivacy = async (e: FormEvent) => {
    e.preventDefault();
    setIsSaving(true);
    try {
      await api.updateSettings('privacy', privacy);
      showMessage('success', 'Privacy settings saved.');
    } catch {
      showMessage('error', 'Failed to save privacy settings.');
    } finally {
      setIsSaving(false);
    }
  };

  const saveNotifications = async (e: FormEvent) => {
    e.preventDefault();
    setIsSaving(true);
    try {
      await api.updateSettings('notifications', notifications);
      showMessage('success', 'Notification settings saved.');
    } catch {
      showMessage('error', 'Failed to save notification settings.');
    } finally {
      setIsSaving(false);
    }
  };

  const changePassword = async (e: FormEvent) => {
    e.preventDefault();
    if (newPassword !== confirmPassword) {
      showMessage('error', 'New passwords do not match.');
      return;
    }
    if (newPassword.length < 8) {
      showMessage('error', 'Password must be at least 8 characters.');
      return;
    }
    setIsSaving(true);
    try {
      await api.changePassword(currentPassword, newPassword);
      setCurrentPassword('');
      setNewPassword('');
      setConfirmPassword('');
      showMessage('success', 'Password changed successfully.');
    } catch {
      showMessage('error', 'Failed to change password. Check your current password.');
    } finally {
      setIsSaving(false);
    }
  };

  const exportData = async () => {
    try {
      await api.exportData();
      showMessage('success', 'Data export started. You will receive an email with a download link.');
    } catch {
      showMessage('error', 'Failed to start data export.');
    }
  };

  const deactivateAccount = async () => {
    try {
      await api.deactivateAccount();
      logout();
    } catch {
      showMessage('error', 'Failed to deactivate account.');
    }
  };

  const deleteAccount = async () => {
    if (deleteConfirmText !== user?.handle) return;
    try {
      await api.deleteAccount();
      logout();
    } catch {
      showMessage('error', 'Failed to delete account.');
    }
  };

  const startMfaSetup = async () => {
    try {
      const data = await api.setupMfa();
      setMfa((prev) => ({
        ...prev,
        qr_code: data.qr_code,
        secret: data.secret,
      }));
      setMfaSetupStep('setup');
    } catch {
      showMessage('error', 'Failed to start 2FA setup.');
    }
  };

  const verifyMfa = async (e: FormEvent) => {
    e.preventDefault();
    try {
      const data = await api.confirmMfa(mfaCode);
      setMfa({ enabled: true, backup_codes: data.backup_codes });
      setMfaCode('');
      setMfaSetupStep('backup');
      showMessage('success', 'Two-factor authentication enabled.');
    } catch {
      showMessage('error', 'Invalid verification code.');
    }
  };

  const disableMfa = async () => {
    try {
      await api.disableMfa();
      setMfa({ enabled: false });
      setMfaSetupStep('idle');
      showMessage('success', 'Two-factor authentication disabled.');
    } catch {
      showMessage('error', 'Failed to disable 2FA.');
    }
  };

  if (authLoading || isLoading) {
    return (
      <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
        <Nav />
        <div className="flex justify-center py-20">
          <LoadingSpinner />
        </div>
      </div>
    );
  }

  if (!user) return null;

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      <Nav />
      <main className="mx-auto max-w-3xl px-4 py-6">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-50 mb-6">
          Settings
        </h1>

        {message && (
          <div
            className={`mb-6 rounded-lg border p-3 text-sm ${
              message.type === 'success'
                ? 'border-green-200 dark:border-green-900 bg-green-50 dark:bg-green-950/50 text-green-700 dark:text-green-400'
                : 'border-red-200 dark:border-red-900 bg-red-50 dark:bg-red-950/50 text-red-700 dark:text-red-400'
            }`}
            role="alert"
          >
            {message.text}
          </div>
        )}

        <div className="flex flex-col sm:flex-row gap-6">
          {/* Sidebar */}
          <nav
            className="flex sm:flex-col gap-1 sm:w-48 flex-shrink-0 overflow-x-auto sm:overflow-visible"
            aria-label="Settings sections"
          >
            {sections.map((section) => (
              <button
                key={section.key}
                onClick={() => setActiveSection(section.key)}
                className={`flex items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium whitespace-nowrap transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 ${
                  activeSection === section.key
                    ? 'bg-brand-50 dark:bg-brand-900/30 text-brand-700 dark:text-brand-300'
                    : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-900'
                }`}
                aria-current={activeSection === section.key ? 'page' : undefined}
              >
                <section.icon className="h-4 w-4" aria-hidden="true" />
                {section.label}
              </button>
            ))}
          </nav>

          {/* Content */}
          <div className="flex-1 min-w-0">
            {/* Profile Section */}
            {activeSection === 'profile' && (
              <form onSubmit={saveProfile} className="space-y-6">
                <div className="rounded-xl border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-6">
                  <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-50 mb-4">
                    Profile
                  </h2>

                  {/* Avatar */}
                  <div className="flex items-center gap-4 mb-6">
                    <div className="relative h-20 w-20 rounded-full overflow-hidden bg-gray-200 dark:bg-gray-800">
                      {profile.avatar_url ? (
                        <Image
                          src={profile.avatar_url}
                          alt="Your avatar"
                          fill
                          className="object-cover"
                        />
                      ) : (
                        <span className="flex h-full w-full items-center justify-center text-2xl font-bold text-gray-400">
                          {user.handle?.[0]?.toUpperCase()}
                        </span>
                      )}
                    </div>
                    <div>
                      <input
                        ref={avatarInputRef}
                        type="file"
                        accept="image/*"
                        onChange={handleAvatarChange}
                        className="hidden"
                        aria-label="Upload avatar"
                      />
                      <button
                        type="button"
                        onClick={() => avatarInputRef.current?.click()}
                        className="inline-flex items-center gap-1.5 rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 px-3 py-1.5 text-sm font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
                      >
                        <Camera className="h-4 w-4" aria-hidden="true" />
                        Change avatar
                      </button>
                    </div>
                  </div>

                  {/* Handle (read-only) */}
                  <div className="mb-4">
                    <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1.5">
                      Handle
                    </label>
                    <input
                      type="text"
                      value={`@${user.handle}`}
                      readOnly
                      className="block w-full rounded-lg border border-gray-200 dark:border-gray-800 bg-gray-50 dark:bg-gray-950 px-3.5 py-2.5 text-sm text-gray-500 dark:text-gray-400 cursor-not-allowed"
                      aria-label="Handle (cannot be changed)"
                    />
                  </div>

                  {/* Display name */}
                  <div className="mb-4">
                    <label
                      htmlFor="display-name"
                      className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1.5"
                    >
                      Display name
                    </label>
                    <input
                      id="display-name"
                      type="text"
                      value={profile.display_name}
                      onChange={(e) =>
                        setProfile((p) => ({ ...p, display_name: e.target.value }))
                      }
                      maxLength={50}
                      className="block w-full rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 px-3.5 py-2.5 text-sm text-gray-900 dark:text-gray-100 focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 focus:outline-none transition-colors"
                    />
                  </div>

                  {/* Bio */}
                  <div>
                    <label
                      htmlFor="bio"
                      className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1.5"
                    >
                      Bio
                    </label>
                    <textarea
                      id="bio"
                      value={profile.bio}
                      onChange={(e) =>
                        setProfile((p) => ({ ...p, bio: e.target.value }))
                      }
                      rows={4}
                      maxLength={500}
                      className="block w-full rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 px-3.5 py-2.5 text-sm text-gray-900 dark:text-gray-100 focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 focus:outline-none transition-colors resize-none"
                    />
                    <p className="mt-1 text-xs text-gray-400">
                      {profile.bio.length}/500
                    </p>
                  </div>
                </div>

                <div className="flex justify-end">
                  <Button type="submit" disabled={isSaving} variant="primary">
                    {isSaving ? (
                      <span className="inline-flex items-center gap-2">
                        <LoadingSpinner />
                        Saving...
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1.5">
                        <Save className="h-4 w-4" aria-hidden="true" />
                        Save changes
                      </span>
                    )}
                  </Button>
                </div>
              </form>
            )}

            {/* Privacy Section */}
            {activeSection === 'privacy' && (
              <form onSubmit={savePrivacy} className="space-y-6">
                <div className="rounded-xl border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-6">
                  <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-50 mb-4">
                    Privacy
                  </h2>

                  <div className="space-y-5">
                    <fieldset>
                      <legend className="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                        Profile visibility
                      </legend>
                      <div className="space-y-2">
                        {[
                          { value: 'public', label: 'Public', desc: 'Anyone can see your profile' },
                          { value: 'followers', label: 'Followers only', desc: 'Only followers can see your posts' },
                          { value: 'private', label: 'Private', desc: 'Approve each follow request manually' },
                        ].map((option) => (
                          <label
                            key={option.value}
                            className="flex items-start gap-3 rounded-lg p-2 hover:bg-gray-50 dark:hover:bg-gray-800 cursor-pointer"
                          >
                            <input
                              type="radio"
                              name="profile_visibility"
                              value={option.value}
                              checked={privacy.profile_visibility === option.value}
                              onChange={(e) =>
                                setPrivacy((p) => ({
                                  ...p,
                                  profile_visibility: e.target.value as PrivacySettings['profile_visibility'],
                                }))
                              }
                              className="mt-1 h-4 w-4 border-gray-300 dark:border-gray-700 text-brand-600 focus:ring-brand-500"
                            />
                            <div>
                              <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                                {option.label}
                              </p>
                              <p className="text-xs text-gray-500 dark:text-gray-400">
                                {option.desc}
                              </p>
                            </div>
                          </label>
                        ))}
                      </div>
                    </fieldset>

                    <fieldset>
                      <legend className="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                        Who can send you direct messages
                      </legend>
                      <div className="space-y-2">
                        {[
                          { value: 'everyone', label: 'Everyone' },
                          { value: 'followers', label: 'Followers only' },
                          { value: 'nobody', label: 'Nobody' },
                        ].map((option) => (
                          <label
                            key={option.value}
                            className="flex items-center gap-3 rounded-lg p-2 hover:bg-gray-50 dark:hover:bg-gray-800 cursor-pointer"
                          >
                            <input
                              type="radio"
                              name="dm_policy"
                              value={option.value}
                              checked={privacy.dm_policy === option.value}
                              onChange={(e) =>
                                setPrivacy((p) => ({
                                  ...p,
                                  dm_policy: e.target.value as PrivacySettings['dm_policy'],
                                }))
                              }
                              className="h-4 w-4 border-gray-300 dark:border-gray-700 text-brand-600 focus:ring-brand-500"
                            />
                            <span className="text-sm text-gray-900 dark:text-gray-100">
                              {option.label}
                            </span>
                          </label>
                        ))}
                      </div>
                    </fieldset>

                    <div className="flex items-center justify-between">
                      <div>
                        <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                          Searchable
                        </p>
                        <p className="text-xs text-gray-500 dark:text-gray-400">
                          Allow your profile to appear in search results
                        </p>
                      </div>
                      <button
                        type="button"
                        role="switch"
                        aria-checked={privacy.searchable}
                        onClick={() =>
                          setPrivacy((p) => ({ ...p, searchable: !p.searchable }))
                        }
                        className={`relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 ${
                          privacy.searchable
                            ? 'bg-brand-600'
                            : 'bg-gray-200 dark:bg-gray-700'
                        }`}
                      >
                        <span
                          className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition-transform ${
                            privacy.searchable ? 'translate-x-5' : 'translate-x-0'
                          }`}
                        />
                      </button>
                    </div>
                  </div>
                </div>

                <div className="flex justify-end">
                  <Button type="submit" disabled={isSaving} variant="primary">
                    {isSaving ? (
                      <span className="inline-flex items-center gap-2">
                        <LoadingSpinner />
                        Saving...
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1.5">
                        <Save className="h-4 w-4" aria-hidden="true" />
                        Save changes
                      </span>
                    )}
                  </Button>
                </div>
              </form>
            )}

            {/* Notifications Section */}
            {activeSection === 'notifications' && (
              <form onSubmit={saveNotifications} className="space-y-6">
                <div className="rounded-xl border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-6">
                  <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-50 mb-4">
                    Notifications
                  </h2>

                  <div className="space-y-4">
                    {(
                      [
                        { key: 'likes', label: 'Likes', desc: 'When someone likes your post' },
                        { key: 'replies', label: 'Replies', desc: 'When someone replies to your post' },
                        { key: 'follows', label: 'Follows', desc: 'When someone follows you' },
                        { key: 'mentions', label: 'Mentions', desc: 'When someone mentions you' },
                        { key: 'reposts', label: 'Reposts', desc: 'When someone reposts your post' },
                        { key: 'polls', label: 'Polls', desc: 'When a poll you voted in ends' },
                        { key: 'email_digest', label: 'Email digest', desc: 'Weekly summary of activity' },
                      ] as const
                    ).map((item) => (
                      <div
                        key={item.key}
                        className="flex items-center justify-between"
                      >
                        <div>
                          <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                            {item.label}
                          </p>
                          <p className="text-xs text-gray-500 dark:text-gray-400">
                            {item.desc}
                          </p>
                        </div>
                        <button
                          type="button"
                          role="switch"
                          aria-checked={notifications[item.key]}
                          aria-label={`${item.label} notifications`}
                          onClick={() =>
                            setNotifications((n) => ({
                              ...n,
                              [item.key]: !n[item.key],
                            }))
                          }
                          className={`relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 ${
                            notifications[item.key]
                              ? 'bg-brand-600'
                              : 'bg-gray-200 dark:bg-gray-700'
                          }`}
                        >
                          <span
                            className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition-transform ${
                              notifications[item.key]
                                ? 'translate-x-5'
                                : 'translate-x-0'
                            }`}
                          />
                        </button>
                      </div>
                    ))}
                  </div>
                </div>

                <div className="flex justify-end">
                  <Button type="submit" disabled={isSaving} variant="primary">
                    {isSaving ? (
                      <span className="inline-flex items-center gap-2">
                        <LoadingSpinner />
                        Saving...
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1.5">
                        <Save className="h-4 w-4" aria-hidden="true" />
                        Save changes
                      </span>
                    )}
                  </Button>
                </div>
              </form>
            )}

            {/* Account Section */}
            {activeSection === 'account' && (
              <div className="space-y-6">
                {/* Change password */}
                <form
                  onSubmit={changePassword}
                  className="rounded-xl border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-6"
                >
                  <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-50 mb-4">
                    Change password
                  </h2>
                  <div className="space-y-4">
                    <div>
                      <label
                        htmlFor="current-password"
                        className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1.5"
                      >
                        Current password
                      </label>
                      <div className="relative">
                        <input
                          id="current-password"
                          type={showPasswords ? 'text' : 'password'}
                          autoComplete="current-password"
                          value={currentPassword}
                          onChange={(e) => setCurrentPassword(e.target.value)}
                          className="block w-full rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 px-3.5 py-2.5 pr-10 text-sm text-gray-900 dark:text-gray-100 focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 focus:outline-none transition-colors"
                        />
                        <button
                          type="button"
                          onClick={() => setShowPasswords(!showPasswords)}
                          className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
                          aria-label={showPasswords ? 'Hide passwords' : 'Show passwords'}
                        >
                          {showPasswords ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                        </button>
                      </div>
                    </div>
                    <div>
                      <label
                        htmlFor="new-password"
                        className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1.5"
                      >
                        New password
                      </label>
                      <input
                        id="new-password"
                        type={showPasswords ? 'text' : 'password'}
                        autoComplete="new-password"
                        value={newPassword}
                        onChange={(e) => setNewPassword(e.target.value)}
                        className="block w-full rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 px-3.5 py-2.5 text-sm text-gray-900 dark:text-gray-100 focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 focus:outline-none transition-colors"
                      />
                    </div>
                    <div>
                      <label
                        htmlFor="confirm-new-password"
                        className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1.5"
                      >
                        Confirm new password
                      </label>
                      <input
                        id="confirm-new-password"
                        type={showPasswords ? 'text' : 'password'}
                        autoComplete="new-password"
                        value={confirmPassword}
                        onChange={(e) => setConfirmPassword(e.target.value)}
                        className="block w-full rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 px-3.5 py-2.5 text-sm text-gray-900 dark:text-gray-100 focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 focus:outline-none transition-colors"
                      />
                    </div>
                    <div className="flex justify-end">
                      <Button
                        type="submit"
                        disabled={!currentPassword || !newPassword || !confirmPassword || isSaving}
                        variant="primary"
                      >
                        Change password
                      </Button>
                    </div>
                  </div>
                </form>

                {/* Export data */}
                <div className="rounded-xl border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-6">
                  <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-50 mb-2">
                    Export your data
                  </h2>
                  <p className="text-sm text-gray-600 dark:text-gray-400 mb-4">
                    Download a copy of your posts, profile, and account data.
                  </p>
                  <button
                    type="button"
                    onClick={exportData}
                    className="inline-flex items-center gap-1.5 rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 px-4 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600"
                  >
                    <Download className="h-4 w-4" aria-hidden="true" />
                    Request export
                  </button>
                </div>

                {/* Deactivate */}
                <div className="rounded-xl border border-orange-200 dark:border-orange-900 bg-orange-50 dark:bg-orange-950/30 p-6">
                  <h2 className="text-lg font-semibold text-orange-800 dark:text-orange-200 mb-2">
                    Deactivate account
                  </h2>
                  <p className="text-sm text-orange-700 dark:text-orange-300 mb-4">
                    Temporarily disable your account. Your data will be preserved and you can reactivate at any time.
                  </p>
                  <button
                    type="button"
                    onClick={deactivateAccount}
                    className="rounded-lg border border-orange-300 dark:border-orange-700 bg-white dark:bg-orange-900/30 px-4 py-2 text-sm font-medium text-orange-700 dark:text-orange-300 hover:bg-orange-100 dark:hover:bg-orange-900/50 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
                  >
                    Deactivate account
                  </button>
                </div>

                {/* Delete */}
                <div className="rounded-xl border border-red-200 dark:border-red-900 bg-red-50 dark:bg-red-950/30 p-6">
                  <div className="flex items-start gap-3">
                    <AlertTriangle className="h-5 w-5 text-red-500 flex-shrink-0 mt-0.5" aria-hidden="true" />
                    <div className="flex-1">
                      <h2 className="text-lg font-semibold text-red-800 dark:text-red-200 mb-2">
                        Delete account
                      </h2>
                      <p className="text-sm text-red-700 dark:text-red-300 mb-4">
                        Permanently delete your account and all associated data. This action cannot be undone.
                      </p>
                      {showDeleteConfirm ? (
                        <div className="space-y-3">
                          <p className="text-sm text-red-700 dark:text-red-300">
                            Type{' '}
                            <span className="font-mono font-bold">
                              {user.handle}
                            </span>{' '}
                            to confirm:
                          </p>
                          <input
                            type="text"
                            value={deleteConfirmText}
                            onChange={(e) => setDeleteConfirmText(e.target.value)}
                            className="block w-full rounded-lg border border-red-300 dark:border-red-700 bg-white dark:bg-red-900/20 px-3.5 py-2.5 text-sm text-gray-900 dark:text-gray-100 focus:border-red-500 focus:ring-2 focus:ring-red-500/20 focus:outline-none"
                            aria-label="Type your handle to confirm deletion"
                          />
                          <div className="flex gap-2">
                            <button
                              type="button"
                              onClick={deleteAccount}
                              disabled={deleteConfirmText !== user.handle}
                              className="rounded-lg bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                            >
                              Delete forever
                            </button>
                            <button
                              type="button"
                              onClick={() => {
                                setShowDeleteConfirm(false);
                                setDeleteConfirmText('');
                              }}
                              className="rounded-lg border border-gray-300 dark:border-gray-700 px-4 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
                            >
                              Cancel
                            </button>
                          </div>
                        </div>
                      ) : (
                        <button
                          type="button"
                          onClick={() => setShowDeleteConfirm(true)}
                          className="rounded-lg bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600"
                        >
                          Delete my account
                        </button>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* MFA Section */}
            {activeSection === 'mfa' && (
              <div className="rounded-xl border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-6">
                <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-50 mb-4">
                  Two-factor authentication
                </h2>

                {mfa.enabled && mfaSetupStep !== 'backup' ? (
                  <div>
                    <div className="flex items-center gap-2 mb-4">
                      <div className="h-2 w-2 rounded-full bg-green-500" />
                      <p className="text-sm font-medium text-green-700 dark:text-green-400">
                        Two-factor authentication is enabled
                      </p>
                    </div>
                    <button
                      type="button"
                      onClick={disableMfa}
                      className="rounded-lg border border-red-300 dark:border-red-700 px-4 py-2 text-sm font-medium text-red-700 dark:text-red-300 hover:bg-red-50 dark:hover:bg-red-900/30 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600"
                    >
                      Disable 2FA
                    </button>
                  </div>
                ) : mfaSetupStep === 'idle' ? (
                  <div>
                    <p className="text-sm text-gray-600 dark:text-gray-400 mb-4">
                      Add an extra layer of security to your account by requiring a verification code from your authenticator app when signing in.
                    </p>
                    <Button onClick={startMfaSetup} variant="primary">
                      Set up 2FA
                    </Button>
                  </div>
                ) : mfaSetupStep === 'setup' ? (
                  <div className="space-y-4">
                    <p className="text-sm text-gray-600 dark:text-gray-400">
                      Scan the QR code below with your authenticator app (such as Google Authenticator or Authy):
                    </p>
                    {mfa.qr_code && (
                      <div className="flex justify-center p-4 bg-white rounded-lg">
                        <img
                          src={mfa.qr_code}
                          alt="QR code for authenticator app"
                          className="h-48 w-48"
                        />
                      </div>
                    )}
                    {mfa.secret && (
                      <div>
                        <p className="text-xs text-gray-500 dark:text-gray-400 mb-1">
                          Or enter this code manually:
                        </p>
                        <code className="block rounded-lg bg-gray-100 dark:bg-gray-800 p-3 text-sm font-mono text-gray-900 dark:text-gray-100 break-all select-all">
                          {mfa.secret}
                        </code>
                      </div>
                    )}
                    <button
                      type="button"
                      onClick={() => setMfaSetupStep('verify')}
                      className="w-full rounded-lg bg-brand-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-brand-700 transition-colors"
                    >
                      Continue
                    </button>
                  </div>
                ) : mfaSetupStep === 'verify' ? (
                  <form onSubmit={verifyMfa} className="space-y-4">
                    <p className="text-sm text-gray-600 dark:text-gray-400">
                      Enter the 6-digit code from your authenticator app to verify setup:
                    </p>
                    <input
                      type="text"
                      inputMode="numeric"
                      autoComplete="one-time-code"
                      maxLength={6}
                      value={mfaCode}
                      onChange={(e) =>
                        setMfaCode(e.target.value.replace(/\D/g, '').slice(0, 6))
                      }
                      className="block w-full rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 px-3.5 py-2.5 text-sm text-center tracking-[0.3em] text-gray-900 dark:text-gray-100 focus:border-brand-500 focus:ring-2 focus:ring-brand-500/20 focus:outline-none"
                      placeholder="000000"
                      aria-label="Verification code"
                    />
                    <button
                      type="submit"
                      disabled={mfaCode.length !== 6}
                      className="w-full rounded-lg bg-brand-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-brand-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                    >
                      Verify and enable
                    </button>
                  </form>
                ) : mfaSetupStep === 'backup' ? (
                  <div className="space-y-4">
                    <div className="flex items-center gap-2 mb-2">
                      <div className="h-2 w-2 rounded-full bg-green-500" />
                      <p className="text-sm font-medium text-green-700 dark:text-green-400">
                        Two-factor authentication is now enabled
                      </p>
                    </div>
                    <p className="text-sm text-gray-600 dark:text-gray-400">
                      Save these backup codes in a safe place. You can use them to sign in if you lose access to your authenticator app. Each code can only be used once.
                    </p>
                    {mfa.backup_codes && (
                      <div className="grid grid-cols-2 gap-2 rounded-lg bg-gray-100 dark:bg-gray-800 p-4">
                        {mfa.backup_codes.map((code, i) => (
                          <code
                            key={i}
                            className="text-sm font-mono text-gray-900 dark:text-gray-100"
                          >
                            {code}
                          </code>
                        ))}
                      </div>
                    )}
                    <button
                      type="button"
                      onClick={() => setMfaSetupStep('idle')}
                      className="w-full rounded-lg bg-brand-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-brand-700 transition-colors"
                    >
                      I have saved my backup codes
                    </button>
                  </div>
                ) : null}
              </div>
            )}
          </div>
        </div>
      </main>
    </div>
  );
}
