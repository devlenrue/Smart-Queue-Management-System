import { z } from 'zod';
import { emailField, nameField, passwordField, phoneField } from './common.validators';

/**
 * Registration always creates a customer. Role is deliberately absent from the
 * schema so it cannot be injected from the client (privilege escalation).
 */
export const registerSchema = z
  .object({
    firstName: nameField('First name'),
    lastName: nameField('Last name'),
    email: emailField,
    phone: phoneField,
    password: passwordField,
    confirmPassword: z.string({ required_error: 'Please confirm your password' }),
  })
  .refine((data) => data.password === data.confirmPassword, {
    message: 'Passwords do not match',
    path: ['confirmPassword'],
  });

export const loginSchema = z.object({
  email: emailField,
  password: z.string({ required_error: 'Password is required' }).min(1, 'Password is required'),
});

export const changePasswordSchema = z
  .object({
    currentPassword: z.string({ required_error: 'Your current password is required' }).min(1, 'Your current password is required'),
    newPassword: passwordField,
    confirmPassword: z.string({ required_error: 'Please confirm your new password' }),
  })
  .refine((data) => data.newPassword === data.confirmPassword, {
    message: 'Passwords do not match',
    path: ['confirmPassword'],
  })
  .refine((data) => data.newPassword !== data.currentPassword, {
    message: 'Your new password must be different from the current one',
    path: ['newPassword'],
  });

export const updateProfileSchema = z.object({
  firstName: nameField('First name').optional(),
  lastName: nameField('Last name').optional(),
  phone: phoneField.optional(),
});

export type RegisterInput = z.infer<typeof registerSchema>;
export type LoginInput = z.infer<typeof loginSchema>;
export type ChangePasswordInput = z.infer<typeof changePasswordSchema>;
export type UpdateProfileInput = z.infer<typeof updateProfileSchema>;
