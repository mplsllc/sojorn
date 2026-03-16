import { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { api } from '@/lib/api';
import { Nav } from '@/components/Nav';
import ProfileContent from './profile-content';

interface Profile {
  id: string;
  handle: string;
  display_name: string;
  bio: string;
  avatar_url: string;
  header_url?: string;
  follower_count: number;
  following_count: number;
  post_count: number;
  created_at: string;
  fields?: Array<{ name: string; value: string; verified_at?: string }>;
  is_following?: boolean;
  is_self?: boolean;
}

interface Props {
  params: { handle: string };
}

async function getProfile(handle: string): Promise<Profile | null> {
  try {
    return await api.getProfileByHandle(handle);
  } catch {
    return null;
  }
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const profile = await getProfile(params.handle);
  if (!profile) {
    return { title: 'User not found' };
  }

  const displayName = profile.display_name || `@${profile.handle}`;
  const description = profile.bio
    ? profile.bio.slice(0, 200)
    : `${displayName} on Sojorn`;

  return {
    title: displayName,
    description,
    openGraph: {
      title: `${displayName} (@${profile.handle})`,
      description,
      images: profile.avatar_url ? [{ url: profile.avatar_url }] : [],
      type: 'profile',
    },
    twitter: {
      card: 'summary',
      title: `${displayName} (@${profile.handle})`,
      description,
      images: profile.avatar_url ? [profile.avatar_url] : [],
    },
  };
}

export default async function ProfilePage({ params }: Props) {
  const profile = await getProfile(params.handle);

  if (!profile) {
    notFound();
  }

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      <Nav />
      <ProfileContent profile={profile} />
    </div>
  );
}
