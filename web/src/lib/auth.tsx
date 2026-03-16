// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import { createContext, useContext, useEffect, useState, useCallback, useRef, ReactNode } from 'react';
import { api, getToken, clearTokens, TOKEN_KEY, REFRESH_KEY } from './api';

interface User {
  id: string;
  handle: string;
  display_name: string;
  avatar_url?: string;
  bio?: string;
  email?: string;
  is_verified?: boolean;
  is_official?: boolean;
}

interface AuthContextType {
  user: User | null;
  token: string | null;
  isLoading: boolean;
  login: (email: string, password: string, mfa?: { mfa_token: string; mfa_code: string }) => Promise<{ mfa_required?: boolean; mfa_token?: string }>;
  logout: () => Promise<void>;
  register: (data: { email: string; password: string; handle: string; display_name?: string; invite_token?: string }) => Promise<void>;
}

const AuthContext = createContext<AuthContextType>({
  user: null,
  token: null,
  isLoading: true,
  login: async () => ({}),
  logout: async () => {},
  register: async () => {},
});

const REFRESH_INTERVAL_MS = 14 * 60 * 1000; // 14 minutes

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [token, setToken] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const refreshTimer = useRef<ReturnType<typeof setInterval> | null>(null);

  const startAutoRefresh = useCallback(() => {
    if (refreshTimer.current) clearInterval(refreshTimer.current);
    refreshTimer.current = setInterval(async () => {
      try {
        const result = await api.refreshToken();
        setToken(result.token);
      } catch {
        setUser(null);
        setToken(null);
        clearTokens();
        if (refreshTimer.current) clearInterval(refreshTimer.current);
      }
    }, REFRESH_INTERVAL_MS);
  }, []);

  const stopAutoRefresh = useCallback(() => {
    if (refreshTimer.current) {
      clearInterval(refreshTimer.current);
      refreshTimer.current = null;
    }
  }, []);

  useEffect(() => {
    const existingToken = getToken();
    if (!existingToken) {
      setIsLoading(false);
      return;
    }

    setToken(existingToken);
    api.getProfile()
      .then((profile: any) => {
        setUser(profile);
        startAutoRefresh();
      })
      .catch(() => {
        clearTokens();
        setUser(null);
        setToken(null);
      })
      .finally(() => setIsLoading(false));

    return () => stopAutoRefresh();
  }, [startAutoRefresh, stopAutoRefresh]);

  const login = useCallback(async (email: string, password: string, mfa?: { mfa_token: string; mfa_code: string }) => {
    const result = await api.login(email, password, mfa);
    if (!result.mfa_required) {
      setUser(result.user);
      setToken(result.token);
      startAutoRefresh();
    }
    return result;
  }, [startAutoRefresh]);

  const register = useCallback(async (data: { email: string; password: string; handle: string; display_name?: string; invite_token?: string }) => {
    const result = await api.register(data);
    setUser(result.user);
    setToken(result.token);
    startAutoRefresh();
  }, [startAutoRefresh]);

  const logout = useCallback(async () => {
    await api.logout();
    setUser(null);
    setToken(null);
    stopAutoRefresh();
  }, [stopAutoRefresh]);

  return (
    <AuthContext.Provider value={{ user, token, isLoading, login, logout, register }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
