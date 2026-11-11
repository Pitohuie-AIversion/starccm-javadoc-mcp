## 2024-11-11 - WPF Form Accessibility using AutomationProperties

**Learning:** When improving accessibility in WPF Windows applications (XAML), standard HTML ARIA attributes do not work. Accessibility must be achieved using `AutomationProperties` in the XAML bindings. For example, to properly label an input field for a screen reader with an existing TextBlock, use `AutomationProperties.LabeledBy="{Binding ElementName=LabelName}"`.
**Action:** When working with `.xaml` files, always look for `AutomationProperties.LabeledBy` or `AutomationProperties.Name` instead of HTML `aria-*` tags, and make sure form fields with separate visual labels are properly linked together for screen reader users.
