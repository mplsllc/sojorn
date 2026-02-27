// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import { createContext, useContext, useEffect, useState, ReactNode } from 'react';
import { api } from './api';

interface AuthContextType {
  isAuthenticated: boolean;
  isLoading: boolean;
  user: any | null;
  login: (email: string, password: string, altchaToken?: string) => Promise<void>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType>({
  isAuthenticated: false,
  isLoading: true,
  user: null,
  login: async () => {},
  logout: async () => {},
});

export function AuthProvider({ children }: { children: ReactNode }) {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [user, setUser] = useState<any | null>(null);

  useEffect(() => {
    // Validate existing cookie by hitting the dashboard endpoint.
    // If the cookie is valid the request succeeds; if not we're unauthenticated.
    api.getDashboardStats()
      .then((data: any) => {
        setIsAuthenticated(true);
        // Restore user info from sessionStorage if available
        if (typeof window !== 'undefined') {
          const stored = sessionStorage.getItem('admin_user');
          if (stored) {
            try { setUser(JSON.parse(stored)); } catch {}
          }
        }
      })
      .catch(() => {
        setIsAuthenticated(false);
      })
      .finally(() => setIsLoading(false));
  }, []);

  const login = async (email: string, password: string, altchaToken?: string) => {
    const data = await api.login(email, password, altchaToken);
    setIsAuthenticated(true);
    setUser(data.user);
    // Store user info (role, handle, etc.) for sidebar filtering on refresh
    if (typeof window !== 'undefined') {
      sessionStorage.setItem('admin_user', JSON.stringify(data.user));
    }
  };

  const logout = async () => {
    await api.logout();
    setIsAuthenticated(false);
    setUser(null);
    if (typeof window !== 'undefined') {
      sessionStorage.removeItem('admin_user');
    }
  };

  return (
    <AuthContext.Provider value={{ isAuthenticated, isLoading, user, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  return useContext(AuthContext);
}
