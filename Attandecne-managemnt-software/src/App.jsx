import { Routes, Route, Navigate } from 'react-router-dom';
import ProtectedRoute from './components/ProtectedRoute';
import Layout from './components/Layout';
import Login from './pages/Login';
import EmployeeDashboard from './pages/EmployeeDashboard';
import AdminDashboard from './pages/AdminDashboard';
import PastAttendance from './pages/PastAttendance';
import EmployeeManagement from './pages/admin/EmployeeManagement';
import AdminAttendance from './pages/admin/AdminAttendance';
import LeaveApprovals from './pages/admin/LeaveApprovals';
import PayrollManagement from './pages/admin/PayrollManagement';
import JobOpenings from './pages/admin/JobOpenings';
import CandidateTracking from './pages/admin/CandidateTracking';
import PerformanceManagement from './pages/admin/PerformanceManagement';
import DocumentManagement from './pages/admin/DocumentManagement';
import ManageExpenses from './pages/admin/ManageExpenses';
import TrainingManagement from './pages/admin/TrainingManagement';
import WorkflowApprovals from './pages/admin/WorkflowApprovals';
import HRAnalytics from './pages/admin/HRAnalytics';
import Profile from './pages/Profile';
import LeaveManagement from './pages/LeaveManagement';
import Payslips from './pages/Payslips';
import Performance from './pages/Performance';
import MyDocuments from './pages/MyDocuments';
import ExpenseClaims from './pages/ExpenseClaims';
import MyLearning from './pages/MyLearning';
import { useAuth } from './hooks/useAuth';

function Home() {
  const { user } = useAuth();
  if (user?.role === 'admin') {
    return <Navigate to="/admin" replace />;
  }
  return <EmployeeDashboard />;
}

function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route element={<ProtectedRoute><Layout /></ProtectedRoute>}>
        <Route path="/" element={<Home />} />
        <Route path="/profile" element={<Profile />} />
        <Route path="/leaves" element={<LeaveManagement />} />
        <Route path="/payslips" element={<Payslips />} />
        <Route path="/performance" element={<Performance />} />
        <Route path="/documents" element={<MyDocuments />} />
        <Route path="/expenses" element={<ExpenseClaims />} />
        <Route path="/learning" element={<MyLearning />} />
        <Route path="/admin" element={<ProtectedRoute adminOnly><AdminDashboard /></ProtectedRoute>} />
        <Route path="/admin/attendance" element={<ProtectedRoute adminOnly><AdminAttendance /></ProtectedRoute>} />
        <Route path="/admin/employees" element={<ProtectedRoute adminOnly><EmployeeManagement /></ProtectedRoute>} />
        <Route path="/admin/leaves" element={<ProtectedRoute adminOnly><LeaveApprovals /></ProtectedRoute>} />
        <Route path="/admin/payroll" element={<ProtectedRoute adminOnly><PayrollManagement /></ProtectedRoute>} />
        <Route path="/admin/jobs" element={<ProtectedRoute adminOnly><JobOpenings /></ProtectedRoute>} />
        <Route path="/admin/candidates" element={<ProtectedRoute adminOnly><CandidateTracking /></ProtectedRoute>} />
        <Route path="/admin/performance" element={<ProtectedRoute adminOnly><PerformanceManagement /></ProtectedRoute>} />
        <Route path="/admin/documents" element={<ProtectedRoute adminOnly><DocumentManagement /></ProtectedRoute>} />
        <Route path="/admin/expenses" element={<ProtectedRoute adminOnly><ManageExpenses /></ProtectedRoute>} />
        <Route path="/admin/training" element={<ProtectedRoute adminOnly><TrainingManagement /></ProtectedRoute>} />
        <Route path="/admin/workflows" element={<ProtectedRoute adminOnly><WorkflowApprovals /></ProtectedRoute>} />
        <Route path="/admin/reports" element={<ProtectedRoute adminOnly><HRAnalytics /></ProtectedRoute>} />
        <Route path="/past-attendance" element={<PastAttendance />} />
      </Route>
      {/* Catch-all route to redirect to login or home */}
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

export default App;
