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
  logout: () => void;
}

const AuthContext = createContext<AuthContextType>({
  isAuthenticated: false,
  isLoading: true,
  user: null,
  login: async () => {},
  logout: () => {},
});

export function AuthProvider({ children }: { children: ReactNode }) {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [user, setUser] = useState<any | null>(null);

  useEffect(() => {
    const token = api.getToken();
    if (token) {
      // Validate token by hitting dashboard
      api.getDashboardStats()
        .then(() => {
          setIsAuthenticated(true);
        })
        .catch(() => {
          api.setToken(null);
          setIsAuthenticated(false);
        })
        .finally(() => setIsLoading(false));
    } else {
      setIsLoading(false);
    }
  }, []);

  const login = async (email: string, password: string, altchaToken?: string) => {
    const data = await api.login(email, password, altchaToken);
    setIsAuthenticated(true);
    setUser(data.user);
  };

  const logout = () => {
    api.setToken(null);
    setIsAuthenticated(false);
    setUser(null);
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
