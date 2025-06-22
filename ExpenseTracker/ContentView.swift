//
//  ContentView.swift
//  ExpenseTracker
//
//  Created by Gregory Paton on 6/14/25.
//

import SwiftUI
import Foundation // For DateFormatter and UUID

// MARK: - Expense Model

// Defines the structure for an individual expense record.
// Identifiable is required for use in SwiftUI Lists.
// Codable allows easy conversion to/from data formats like CSV (via string).
struct Expense: Identifiable, Codable {
    let id: UUID
    var amount: Double
    var tags: [String]   // Now an array of arbitrary tags
    var date: Date       // Date of the purchase

    // Initializes a new Expense instance.
    init(amount: Double, tags: [String], date: Date = Date()) {
        self.id = UUID() // Generate a unique ID for each expense.
        self.amount = amount
        self.tags = tags
        self.date = date
    }

    // Custom initializer for decoding from CSV (where ID is already known).
    init(id: UUID, amount: Double, tags: [String], date: Date) {
        self.id = id
        self.amount = amount
        self.tags = tags
        self.date = date
    }
}

// MARK: - CSV Conversion Extension for [Expense]

extension Array where Element == Expense {
    // Helper function to escape strings for CSV (enclose in quotes if contains comma or quote).
    // This is crucial for handling tags, which might contain commas themselves.
    static func escapeCSVString(_ string: String) -> String {
        let escapedString = string.replacingOccurrences(of: "\"", with: "\"\"") // Escape internal quotes
        if escapedString.contains(",") || escapedString.contains("\n") || escapedString.contains("\"") {
            return "\"\(escapedString)\"" // Enclose in quotes if it contains a comma, newline, or quote.
        }
        return escapedString
    }

    // Converts an array of Expense objects into a CSV formatted string.
    // Each row represents an expense, with fields separated by commas.
    // Tags are joined by a special delimiter (";;") and then escaped for the CSV field.
    func toCSVString() -> String {
        // Define the header row for the CSV file.
        // Updated header to reflect the 'Tags' column.
        let header = "ID,Amount,Tags,Date\n"
        
        // Use a DateFormatter to ensure consistent date formatting in CSV.
        let dateFormatter = ISO8601DateFormatter() // ISO 8601 for consistent date/time.

        // Map each expense to a CSV line.
        let rows = self.map { (expense: Expense) in
            // Join tags into a single string using a specific delimiter, then escape it.
            // Using a delimiter like ";;" makes it less likely to conflict with tag content.
            let tagsString = expense.tags.map { Self.escapeCSVString($0) }.joined(separator: ";;")
            let escapedTags = Self.escapeCSVString(tagsString)

            // Format the date to a string.
            let dateString = dateFormatter.string(from: expense.date)

            // Combine all fields into a CSV line.
            return "\(expense.id.uuidString),\(expense.amount),\(escapedTags),\(dateString)"
        }
        
        // Join the header and all expense rows to form the complete CSV string.
        return header + rows.joined(separator: "\n")
    }

    // Converts a CSV formatted string back into an array of Expense objects.
    static func fromCSVString(_ csvString: String) -> [Expense] {
        var expenses: [Expense] = []
        // Split the CSV string into individual lines.
        let lines = csvString.components(separatedBy: .newlines)
        
        // Ensure there are lines to process and skip the header row.
        guard lines.count > 1 else { return [] }
        
        // Use a DateFormatter to parse dates from the CSV.
        let dateFormatter = ISO8601DateFormatter()

        // Iterate over each line, starting from the second line (after the header).
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue } // Skip empty lines.
            
            // This is a simplified CSV parser. For robust handling of quoted fields
            // that might contain commas or the delimiter ";;", a proper CSV parsing library
            // would be ideal. This basic split assumes simple comma separation for main fields.
            let components = line.components(separatedBy: ",")
            
            // We now expect 4 components: ID, Amount, Tags, Date.
            guard components.count >= 4 else {
                print("Skipping malformed CSV line (incorrect component count): \(line)")
                continue
            }

            // Attempt to parse each component into the correct type.
            if let id = UUID(uuidString: components[0]),
               let amount = Double(components[1]),
               let date = dateFormatter.date(from: components[3]) { // Date is the 4th component (index 3).
                
                // Extract and unescape tags string, then split by delimiter.
                let tagsRawString = components[2].replacingOccurrences(of: "\"", with: "") // Remove CSV-level quotes
                let tags = tagsRawString.components(separatedBy: ";;").filter { !$0.isEmpty } // Split by internal delimiter and filter empty tags

                // Create a new Expense object and add it to the array.
                let expense = Expense(id: id, amount: amount, tags: tags, date: date)
                expenses.append(expense)
            } else {
                print("Failed to parse expense from line: \(line)")
            }
        }
        return expenses
    }
}

// MARK: - Persistence Protocol

// This protocol defines the required methods for any persistence backend.
// By conforming to this protocol, different storage mechanisms can be swapped in.
protocol ExpensePersistence {
    func saveExpenses(_ expenses: [Expense])
    func loadExpenses() -> [Expense]
}

// MARK: - Local File Persistence Manager

// Implements ExpensePersistence using local file storage (Documents directory).
class LocalFilePersistenceManager: ExpensePersistence {
    // Defines the filename for the CSV data.
    private let filename = "expenses.csv"
    
    // Computes the full URL to the CSV file in the app's Documents directory.
    private var fileURL: URL {
        // Get the URL for the user's Documents directory.
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Unable to find documents directory.") // Should not happen in a typical iOS environment.
        }
        // Append the filename to the Documents directory URL.
        return documentsDirectory.appendingPathComponent(filename)
    }

    // Saves an array of Expense objects to the local CSV file.
    func saveExpenses(_ expenses: [Expense]) {
        let csvString = expenses.toCSVString()
        do {
            // Write the CSV string to the file atomically (ensures data integrity).
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Expenses saved to local file: \(fileURL.lastPathComponent)")
        } catch {
            print("Failed to save expenses to local file: \(error.localizedDescription)")
            // In a real app, you might want to show a user-facing error message here.
        }
    }

    // Loads an array of Expense objects from the local CSV file.
    func loadExpenses() -> [Expense] {
        // Check if the file exists before attempting to read.
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("No local CSV file found. Starting with empty data.")
            return []
        }
        
        do {
            // Read the content of the file into a string.
            let csvData = try String(contentsOf: fileURL, encoding: .utf8)
            // Convert the CSV string back into an array of Expense objects.
            return Array.fromCSVString(csvData) // Corrected call
        } catch {
            print("Failed to load expenses from local file: \(error.localizedDescription)")
            // If loading fails, return an empty array to prevent app crash.
            return []
        }
    }
}

// MARK: - Main SwiftUI View

struct ContentView: View {
    // State variables to hold user input for new expenses.
    @State private var amount: String = ""
    @State private var newTag: String = "" // For adding new tags
    @State private var currentTags: [String] = [] // Tags for the current expense being added
    @State private var selectedDate: Date = Date() // State for the selected date, initialized to current date
    
    // State variable to store all recorded expenses.
    @State private var expenses: [Expense] = []
    
    // State for showing alerts (e.g., for validation errors or save/load issues).
    @State private var showingAlert = false
    @State private var alertMessage = ""

    // Inject the persistence manager. This makes it easy to swap implementations.
    // For now, we're using LocalFilePersistenceManager.
    // If you later create a FirebasePersistenceManager, you'd change this line.
    private let persistenceManager: ExpensePersistence = LocalFilePersistenceManager()

    var body: some View {
        NavigationView {
            Form {
                // MARK: - Expense Input Section
                Section("New Expense Details") {
                    HStack {
                        // TextField for the amount. Uses .keyboardType(.decimalPad) for numerical input.
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        
                        // Date Picker, now only showing date component and no label
                        DatePicker(
                            "", // Empty label
                            selection: $selectedDate,
                            displayedComponents: [.date] // Only show date
                        )
                        .padding(.vertical, 8) // Reduced vertical padding to align better
//                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .labelsHidden() // Explicitly hide the label
                    }
                    
                    // Input for new tags
                    HStack {
                        TextField("Add a tag (e.g., Groceries, Dinner)", text: $newTag)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .onSubmit { // Add tag when return key is pressed
                                addTag()
                            }
                        
                        Button("Add") {
                            addTag()
                        }
                        .font(.headline)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    
                    // Display current tags as oval bubbles
                    if !currentTags.isEmpty {
                        // Using a FlexibleLayout or just a simple HStack with wrapping
                        // For simplicity, using a horizontal ScrollView for many tags in a row.
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(currentTags, id: \.self) { tag in
                                    TagBubble(tag: tag) {
                                        removeTag(tag)
                                    }
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    } else {
                        Text("No tags added yet.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.vertical, 5)
                    }
                    
                    // Button to add the new expense.
                    Button("Add Expense") {
                        addExpense()
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(amount.isEmpty || currentTags.isEmpty) // Disable if amount is empty or no tags
                }
                
                // MARK: - Recorded Expenses List Section
                Section("Recorded Expenses") {
                    // Display the list of expenses.
                    ForEach(expenses.sorted(by: { $0.date > $1.date })) { expense in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(String(format: "$%.2f", expense.amount))
                                    .font(.title3)
                                    .fontWeight(.bold)
                                Spacer()
                                // Display both date and time (if time is not midnight) or just date
                                // Note: DateFormatter implicitly handles time if it's not midnight.
                                Text(expense.date, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                // Display time only if it's not midnight, otherwise keep it blank or display only date
                                if !Calendar.current.isDateInToday(expense.date) || Calendar.current.component(.hour, from: expense.date) != 0 || Calendar.current.component(.minute, from: expense.date) != 0 {
                                    Text(expense.date, style: .time)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            // Display tags for each recorded expense
                            if !expense.tags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(expense.tags, id: \.self) { tag in
                                            Text(tag)
                                                .font(.caption2)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.gray.opacity(0.2))
                                                .cornerRadius(10)
                                        }
                                    }
                                }
                            } else {
                                Text("No tags")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    // Add swipe-to-delete functionality.
                    .onDelete(perform: deleteExpense)
                }
            }
            .navigationTitle("My Spending Tracker")
            // Add a toolbar item to save data manually.
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save Data") {
                        saveExpenses() // Now calls the persistence manager
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton() // Provides built-in editing functionality (e.g., delete)
                }
            }
            // Alert for validation errors.
            .alert("Input Error", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            // Load expenses when the view appears.
            .onAppear(perform: loadExpenses) // Now calls the persistence manager
        }
    }

    // MARK: - Tag Management Functions

    // Adds a new tag to the `currentTags` list.
    private func addTag() {
        let trimmedTag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTag.isEmpty && !currentTags.contains(trimmedTag) {
            currentTags.append(trimmedTag)
            newTag = "" // Clear the input field after adding.
        } else if trimmedTag.isEmpty {
            alertMessage = "Please enter a tag."
            showingAlert = true
        } else {
            alertMessage = "This tag already exists."
            showingAlert = true
        }
    }

    // Removes a tag from the `currentTags` list.
    private func removeTag(_ tagToRemove: String) {
        currentTags.removeAll(where: { $0 == tagToRemove })
    }

    // MARK: - Expense Management Functions

    // Validates input and adds a new expense to the list.
    private func addExpense() {
        // Validate amount input.
        guard let amountValue = Double(amount), amountValue > 0 else {
            alertMessage = "Please enter a valid positive amount."
            showingAlert = true
            return
        }
        
//        // Validate that at least one tag is present.
//        guard !currentTags.isEmpty else {
//            alertMessage = "Please add at least one tag for the purchase."
//            showingAlert = true
//            return
//        }

        // Create a new Expense object with the current tags and selected date.
        let newExpense = Expense(amount: amountValue, tags: currentTags, date: selectedDate)
        
        // Add the new expense to the beginning of the array.
        expenses.insert(newExpense, at: 0)
        
        // Clear the input fields and current tags after adding. Reset date to current.
        amount = ""
        newTag = ""
        currentTags = []
        selectedDate = Date() // Reset date to current time for next entry
        
        // Save the updated list using the persistence manager.
        saveExpenses()
    }

    // Deletes expenses from the list.
    private func deleteExpense(at offsets: IndexSet) {
        expenses.remove(atOffsets: offsets)
        // Save the updated list using the persistence manager after deletion.
        saveExpenses()
    }

    // MARK: - Persistence Operations (Delegated to Manager)

    // Calls the persistence manager to save expenses.
    private func saveExpenses() {
        persistenceManager.saveExpenses(expenses)
    }

    // Calls the persistence manager to load expenses.
    private func loadExpenses() {
        expenses = persistenceManager.loadExpenses()
    }
}

// MARK: - TagBubble View

// A reusable SwiftUI view for displaying individual tags as oval bubbles with a delete button.
struct TagBubble: View {
    let tag: String
    var onDelete: () -> Void // Closure to call when the delete button is tapped

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)
                .padding(.leading, 8)
                .lineLimit(1) // Ensure tag doesn't wrap
            
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(PlainButtonStyle()) // To remove default button styling
            .padding(.trailing, 6)
        }
        .padding(.vertical, 5)
        .background(Color.blue.opacity(0.7))
        .foregroundColor(.white)
        .cornerRadius(20) // Makes it an oval/capsule shape
    }
}

// MARK: - Preview Provider (for Xcode Canvas)
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
