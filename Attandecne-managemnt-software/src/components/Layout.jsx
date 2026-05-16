import { useState, useEffect } from 'react';
import { Outlet, Link, useLocation } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth';
import { FaSignOutAlt, FaBuilding, FaUserCircle, FaMapMarkedAlt, FaCalendarAlt, FaUsers, FaUser, FaCalendarCheck, FaMoneyCheckAlt, FaUserTie, FaBriefcase, FaChartLine, FaFileAlt, FaWallet, FaGraduationCap, FaInbox, FaChartPie, FaBars, FaTimes } from 'react-icons/fa';
import Notifications from './Notifications';
import { motion, AnimatePresence } from 'framer-motion';

const NavLink = ({ to, icon, children, exact }) => {
  const location = useLocation();
  const isActive = exact ? location.pathname === to : location.pathname === to;
  return (
    <Link
      to={to}
      className={`flex items-center px-4 py-3 text-sm font-medium rounded-md transition-colors ${
        isActive
          ? 'text-indigo-700 bg-indigo-50'
          : 'text-gray-600 hover:bg-gray-100 hover:text-gray-900'
      }`}
    >
      <span className="mr-3 text-lg">{icon}</span>
      {children}
    </Link>
  );
};

export default function Layout() {
  const { user, logoutContext } = useAuth();
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const location = useLocation();

  // Close menu on route change
  useEffect(() => {
    setIsMenuOpen(false);
  }, [location.pathname]);

  const SidebarContent = () => (
    <>
      {/* Logo */}
      <div className="h-16 flex items-center px-6 border-b border-gray-100 flex-shrink-0">
        <FaBuilding className="text-indigo-600 text-2xl mr-3" />
        <span className="text-lg font-bold text-gray-900 tracking-tight">Core Flow HCM</span>
      </div>

      {/* Nav Links */}
      <div className="flex-1 py-4 space-y-0.5 px-3 overflow-y-auto scrollbar-hide">
        {/* Employee Links */}
        <NavLink to="/" icon={<FaUserCircle />} exact>Dashboard</NavLink>
        {user?.role === 'admin'
          ? <NavLink to="/admin/attendance" icon={<FaCalendarAlt />}>Attendance</NavLink>
          : <NavLink to="/past-attendance" icon={<FaCalendarAlt />}>Attendance</NavLink>
        }
        {user?.role !== 'admin' && (
          <>
            <NavLink to="/leaves" icon={<FaCalendarCheck />}>Leaves</NavLink>
            <NavLink to="/payslips" icon={<FaMoneyCheckAlt />}>Payslips</NavLink>
            <NavLink to="/performance" icon={<FaChartLine />}>Performance</NavLink>
            <NavLink to="/expenses" icon={<FaWallet />}>Expenses</NavLink>
            <NavLink to="/learning" icon={<FaGraduationCap />}>My Learning</NavLink>
            <NavLink to="/documents" icon={<FaFileAlt />}>My Documents</NavLink>
            <NavLink to="/profile" icon={<FaUser />}>My Profile</NavLink>
          </>
        )}

        {/* Admin Links */}
        {user?.role === 'admin' && (
          <>
            <div className="pt-4 pb-2 px-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">
              Admin
            </div>
            <NavLink to="/admin" icon={<FaMapMarkedAlt />}>Location Monitor</NavLink>
            <NavLink to="/admin/employees" icon={<FaUsers />}>Employees</NavLink>
            <NavLink to="/admin/leaves" icon={<FaCalendarCheck />}>Leave Approvals</NavLink>
            <NavLink to="/admin/payroll" icon={<FaMoneyCheckAlt />}>Payroll</NavLink>

            <NavLink to="/admin/performance" icon={<FaChartLine />}>Performance</NavLink>
            <NavLink to="/admin/documents" icon={<FaFileAlt />}>Documents</NavLink>
            <NavLink to="/admin/expenses" icon={<FaWallet />}>Expense Claims</NavLink>

            <NavLink to="/admin/reports" icon={<FaChartPie />}>Reports & Analytics</NavLink>
          </>
        )}
      </div>

      {/* User Footer */}
      <div className="p-4 border-t border-gray-100 bg-gray-50 flex items-center justify-between flex-shrink-0">
        <div className="flex items-center overflow-hidden">
          <img
            className="h-9 w-9 rounded-full object-cover border border-gray-200 flex-shrink-0"
            src={user?.photoURL || `https://ui-avatars.com/api/?name=${encodeURIComponent(user?.name || 'User')}&background=6366f1&color=fff`}
            alt="Profile"
          />
          <div className="ml-3 truncate max-w-[100px]">
            <p className="text-sm font-medium text-gray-900 truncate">{user?.name}</p>
            <p className="text-xs text-gray-500 capitalize">{user?.role}</p>
          </div>
        </div>
        <div className="flex items-center gap-1">
          <Notifications />
          <button
            onClick={logoutContext}
            title="Logout"
            className="p-2 text-gray-400 hover:text-red-600 hover:bg-red-50 rounded-md transition-colors"
          >
            <FaSignOutAlt className="text-lg" />
          </button>
        </div>
      </div>
    </>
  );

  return (
    <div className="flex bg-gray-50 min-h-screen w-full font-sans text-gray-800 overflow-x-hidden">
      
      {/* Mobile Sidebar (Animated) */}
      <AnimatePresence>
        {isMenuOpen && (
          <>
            {/* Backdrop */}
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setIsMenuOpen(false)}
              className="fixed inset-0 bg-black/40 backdrop-blur-sm z-[100] md:hidden"
            />
            {/* Sidebar */}
            <motion.aside
              initial={{ x: '-100%' }}
              animate={{ x: 0 }}
              exit={{ x: '-100%' }}
              transition={{ type: 'spring', damping: 25, stiffness: 200 }}
              className="fixed left-0 top-0 bottom-0 w-72 bg-white z-[101] flex flex-col shadow-2xl md:hidden"
            >
              <SidebarContent />
            </motion.aside>
          </>
        )}
      </AnimatePresence>

      {/* Desktop Sidebar */}
      <aside className="w-64 bg-white border-r border-gray-200 hidden md:flex flex-col shadow-sm sticky top-0 h-screen overflow-hidden">
        <SidebarContent />
      </aside>

      {/* Main content */}
      <main className="flex-1 flex flex-col min-w-0 relative">
        {/* Mobile header */}
        <header className="md:hidden flex items-center justify-between px-4 h-16 bg-white border-b border-gray-200 sticky top-0 z-[90]">
          <div className="flex items-center gap-3">
            <button 
              onClick={() => setIsMenuOpen(true)}
              className="p-2 -ml-2 text-gray-500 hover:bg-gray-100 rounded-lg transition-colors"
            >
              <FaBars className="text-xl" />
            </button>
            <span className="text-lg font-black text-indigo-600 tracking-tight">Core Flow</span>
          </div>
          <div className="flex items-center gap-2">
             <Notifications />
             <div className="h-8 w-8 rounded-full bg-indigo-50 flex items-center justify-center text-indigo-600 text-xs font-bold border border-indigo-100">
                {user?.name?.[0] || 'U'}
             </div>
          </div>
        </header>

        <div className="py-6 sm:py-8 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto w-full">
          <Outlet />
        </div>
      </main>
    </div>
  );
}
