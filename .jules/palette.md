## 2024-05-18 - XAML TextBox Screen Reader Accessibility
**Learning:** TextBoxes in WPF XAML need `AutomationProperties.LabeledBy` bound to their descriptive labels for screen readers to properly associate the form field with its description.
**Action:** Always add `AutomationProperties.LabeledBy="{Binding ElementName=LabelName}"` to text inputs to ensure accessibility for visually impaired users.
