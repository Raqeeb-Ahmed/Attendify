import { useNavigate } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth';
import { FaGoogle, FaUserTie } from 'react-icons/fa';
import { useState, useEffect } from 'react';

export default function Login() {
  const { user, loginContext } = useAuth();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    if (user) {
      if (user.role === 'admin') {
        navigate('/admin');
      } else {
        navigate('/');
      }
    }
  }, [user, navigate]);

  const handleLogin = async () => {
    setLoading(true);
    setError('');
    try {
      await loginContext();
    } catch (error) {
      console.error('Login error:', error);
      let errorMsg = error.message;
      if (error.code === 'auth/popup-closed-by-user') {
        errorMsg = 'Login popup was closed. Please try again.';
      } else if (error.code === 'auth/popup-blocked') {
        errorMsg = 'Pop-up was blocked. Please allow pop-ups and try again.';
      } else if (error.code === 'auth/network-request-failed') {
        errorMsg = 'Network error. Please check your connection.';
      }
      setError(errorMsg);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="flex h-screen w-full items-center justify-center bg-gradient-to-br from-indigo-50 to-blue-50">
      <div className="w-full max-w-md p-8 bg-white rounded-xl shadow-lg border border-gray-100">
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-indigo-100 text-indigo-600 mb-4">
             <FaUserTie className="w-8 h-8" />
          </div>
          <h2 className="text-3xl font-bold text-gray-900">Company Portal</h2>
          <p className="mt-2 text-sm text-gray-500">Sign in with your corporate Google account.</p>
        </div>
        
        {error && (
          <div className="mb-4 p-4 bg-red-50 border border-red-200 rounded-lg">
            <p className="text-sm text-red-700">{error}</p>
          </div>
        )}
        
        <button
          onClick={handleLogin}
          disabled={loading}
          className="w-full flex items-center justify-center px-4 py-3 border border-gray-300 text-sm font-medium rounded-lg text-gray-700 bg-white hover:bg-gray-50 transition-colors shadow-sm disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <FaGoogle className="mr-3 text-red-500" />
          {loading ? 'Signing in...' : 'Sign in with Google'}
        </button>
      </div>
    </div>
  );
}
