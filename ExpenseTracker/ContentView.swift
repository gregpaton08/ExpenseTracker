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
    var location: String // Tag for where the purchase was made
    var item: String     // Tag for what the purchase was
    var date: Date       // Date of the purchase

    // Initializes a new Expense instance.
    init(amount: Double, location: String, item: String, date: Date = Date()) {
        self.id = UUID() // Generate a unique ID for each expense.
        self.amount = amount
        self.location = location
        self.item = item
        self.date = date
    }

    // Custom initializer for decoding from CSV (where ID is already known).
    init(id: UUID, amount: Double, location: String, item: String, date: Date) {
        self.id = id
        self.amount = amount
        self.location = location
        self.item = item
        self.date = date
    }
}

// MARK: - CSV Conversion Extension for [Expense]

extension Array where Element == Expense {
    // Helper function to escape strings for CSV (enclose in quotes if contains comma or quote).
    // Moved outside the `toCSVString` method to simplify its context.
    static func escapeCSVString(_ string: String) -> String {
        let escapedString = string.replacingOccurrences(of: "\"", with: "\"\"") // Escape internal quotes
        if escapedString.contains(",") || escapedString.contains("\n") || escapedString.contains("\"") {
            return "\"\(escapedString)\"" // Enclose in quotes if it contains a comma, newline, or quote.
        }
        return escapedString
    }

    // Converts an array of Expense objects into a CSV formatted string.
    // Each row represents an expense, with fields separated by commas.
    // Handles commas within string fields by enclosing them in double quotes.
    func toCSVString() -> String {
        // Define the header row for the CSV file.
        let header = "ID,Amount,Location,Item,Date\n"
        
        // Use a DateFormatter to ensure consistent date formatting in CSV.
        let dateFormatter = ISO8601DateFormatter() // ISO 8601 for consistent date/time.

        // Map each expense to a CSV line.
        let rows = self.map { (expense: Expense) in
            // Format the date to a string.
            let dateString = dateFormatter.string(from: expense.date)

            // Combine all fields into a CSV line, using the static helper for escaping.
            return "\(expense.id.uuidString),\(expense.amount),\(Self.escapeCSVString(expense.location)),\(Self.escapeCSVString(expense.item)),\(dateString)"
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
            
            // Basic splitting by comma. This is a simplified parser and might
            // not handle complex CSV cases with quoted commas perfectly without a proper CSV parser library.
            // For a robust solution, consider a dedicated CSV parsing library.
            let components = line.components(separatedBy: ",")
            
            // We expect 5 components: ID, Amount, Location, Item, Date.
            guard components.count >= 5 else {
                print("Skipping malformed CSV line: \(line)")
                continue
            }

            // Attempt to parse each component into the correct type.
            if let id = UUID(uuidString: components[0]),
               let amount = Double(components[1]),
               let date = dateFormatter.date(from: components[4]) { // Date is the 5th component (index 4).
                
                // Location and Item tags might be quoted; remove quotes if present.
                let location = components[2].replacingOccurrences(of: "\"", with: "")
                let item = components[3].replacingOccurrences(of: "\"", with: "")

                // Create a new Expense object and add it to the array.
                let expense = Expense(id: id, amount: amount, location: location, item: item, date: date)
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
    @State private var locationTag: String = ""
    @State private var itemTag: String = ""
    
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
                    // TextField for the amount. Uses .keyboardType(.decimalPad) for numerical input.
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    
                    // TextField for the location tag.
                    TextField("Where was this purchase?", text: $locationTag)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    
                    // TextField for the item tag.
                    TextField("What was the purchase?", text: $itemTag)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    
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
                }
                
                // MARK: - Expense List Section
                Section("Recorded Expenses") {
                    // Display the list of expenses.
                    // ForEach is used for dynamic lists that can be deleted.
                    ForEach(expenses.sorted(by: { $0.date > $1.date })) { expense in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(expense.item)
                                    .font(.headline)
                                Text(expense.location)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                Text(expense.date, style: .date) // Display date
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(String(format: "$%.2f", expense.amount)) // Format amount to 2 decimal places.
                                .font(.title3)
                                .fontWeight(.bold)
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

    // MARK: - Helper Functions

    // Validates input and adds a new expense to the list.
    private func addExpense() {
        // Validate amount input.
        guard let amountValue = Double(amount), amountValue > 0 else {
            alertMessage = "Please enter a valid positive amount."
            showingAlert = true
            return
        }
        
        // Validate tags are not empty.
        guard !locationTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = "Please enter a location tag."
            showingAlert = true
            return
        }
        guard !itemTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = "Please enter an item tag."
            showingAlert = true
            return
        }

        // Create a new Expense object.
        let newExpense = Expense(amount: amountValue, location: locationTag.trimmingCharacters(in: .whitespacesAndNewlines), item: itemTag.trimmingCharacters(in: .whitespacesAndNewlines))
        
        // Add the new expense to the beginning of the array.
        expenses.insert(newExpense, at: 0)
        
        // Clear the input fields.
        amount = ""
        locationTag = ""
        itemTag = ""
        
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

// MARK: - Preview Provider (for Xcode Canvas)
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
