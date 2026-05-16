export const DEPARTMENTS = [
  'Human Resources',
  'Engineering',
  'Design',
  'Marketing',
  'Sales',
  'Finance',
  'Operations',
  'Management'
];

export const DESIGNATIONS = [
  'Intern',
  'Software Developer',
  'Manager',
  'HR Manager',
  'Accountant',
  'Sales Executive',
  'Visa Officer',
  'E-Visa Officer',
  'Ticketing Officer',
  'Visa Consultant',
  'Director',
  'CEO'
];

export const EMPLOYEE_STATUS = [
  { label: 'Active', color: 'bg-green-100 text-green-800' },
  { label: 'On Leave', color: 'bg-yellow-100 text-yellow-800' },
  { label: 'Resigned', color: 'bg-gray-100 text-gray-800' },
  { label: 'Terminated', color: 'bg-red-100 text-red-800' }
];

export const SHIFTS = [
  { id: 'morning', label: 'Morning Shift', start: '09:00', end: '18:00', gracePeriod: 15 },
  { id: 'evening', label: 'Evening Shift', start: '14:00', end: '22:00', gracePeriod: 15 },
  { id: 'night', label: 'Night Shift', start: '22:00', end: '06:00', gracePeriod: 15 }
];

export const LEAVE_TYPES = [
  { id: 'annual', label: 'Annual Leave', defaultBalance: 20 },
  { id: 'sick', label: 'Sick Leave', defaultBalance: 10 },
  { id: 'casual', label: 'Casual Leave', defaultBalance: 10 },
  { id: 'unpaid', label: 'Unpaid Leave', defaultBalance: 0 }
];

export const LEAVE_STATUS = [
  { id: 'pending', label: 'Pending', color: 'bg-yellow-100 text-yellow-800' },
  { id: 'approved', label: 'Approved', color: 'bg-green-100 text-green-800' },
  { id: 'rejected', label: 'Rejected', color: 'bg-red-100 text-red-800' }
];

export const CURRENCY = 'PKR';
export const DEFAULT_TAX_RATE = 10; // 10%

export const JOB_STAGES = [
  { id: 'applied', label: 'Applied', color: 'bg-blue-100 text-blue-800' },
  { id: 'interviewing', label: 'Interviewing', color: 'bg-purple-100 text-purple-800' },
  { id: 'offered', label: 'Offered', color: 'bg-indigo-100 text-indigo-800' },
  { id: 'hired', label: 'Hired', color: 'bg-green-100 text-green-800' },
  { id: 'rejected', label: 'Rejected', color: 'bg-red-100 text-red-800' }
];

export const JOB_TYPES = ['Full-time', 'Part-time', 'Contract', 'Remote'];

export const PERFORMANCE_RATINGS = [
  { value: 5, label: 'Outstanding', color: 'text-green-600' },
  { value: 4, label: 'Exceeds Expectations', color: 'text-blue-600' },
  { value: 3, label: 'Meets Expectations', color: 'text-yellow-600' },
  { value: 2, label: 'Needs Improvement', color: 'text-orange-600' },
  { value: 1, label: 'Unsatisfactory', color: 'text-red-600' }
];

export const DOCUMENT_TYPES = [
  { id: 'offer_letter', label: 'Offer Letter' },
  { id: 'contract', label: 'Employment Contract' },
  { id: 'warning', label: 'Warning Letter' },
  { id: 'experience', label: 'Experience Certificate' },
  { id: 'payslip', label: 'Payslip' }
];

export const EXPENSE_CATEGORIES = [
  'Travel',
  'Meals',
  'Supplies',
  'Equipment',
  'Software',
  'Other'
];

export const EXPENSE_STATUS = [
  { id: 'pending', label: 'Pending', color: 'bg-yellow-100 text-yellow-800' },
  { id: 'approved', label: 'Approved', color: 'bg-green-100 text-green-800' },
  { id: 'rejected', label: 'Rejected', color: 'bg-red-100 text-red-800' }
];

export const TRAINING_STATUS = [
  { id: 'assigned', label: 'Assigned', color: 'bg-blue-100 text-blue-800' },
  { id: 'in_progress', label: 'In Progress', color: 'bg-yellow-100 text-yellow-800' },
  { id: 'completed', label: 'Completed', color: 'bg-green-100 text-green-800' }
];

export const TRAINING_LEVELS = ['Beginner', 'Intermediate', 'Advanced'];
