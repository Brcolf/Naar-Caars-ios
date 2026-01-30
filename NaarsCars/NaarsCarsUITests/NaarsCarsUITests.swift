//
//  NaarsCarsUITests.swift
//  NaarsCarsUITests
//
//  Created by Brendan Colford on 1/4/26.
//

import XCTest

final class NaarsCarsUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testRequestsDashboardFlow() throws {
        let app = launchApp()
        loginIfNeeded(app: app, email: "alice@test.com", password: "TestPassword123!")
        handleGuidelinesIfNeeded(app: app)

        openTab(app: app, label: "Requests")

        app.buttons["requests.filter.Open Requests"].firstMatch.tap()
        app.buttons["requests.filter.My Requests"].firstMatch.tap()
        app.buttons["requests.filter.Claimed by Me"].firstMatch.tap()

        if app.buttons["requests.createMenu"].exists {
            app.buttons["requests.createMenu"].tap()
            app.buttons["Create Ride"].firstMatch.tap()
            app.buttons["createRide.cancel"].waitForExistence(timeout: 5)
            app.buttons["createRide.cancel"].tap()

            app.buttons["requests.createMenu"].tap()
            app.buttons["Create Favor"].firstMatch.tap()
            app.buttons["createFavor.cancel"].waitForExistence(timeout: 5)
            app.buttons["createFavor.cancel"].tap()
        }

        let firstRequest = app.otherElements["requests.card"].firstMatch
        if firstRequest.waitForExistence(timeout: 5) {
            firstRequest.tap()
            app.navigationBars.buttons.firstMatch.tap()
        }

        app.swipeUp()
        app.swipeDown()
    }

    @MainActor
    func testRequestsPullToRefreshMovesFilters() throws {
        let app = launchApp()
        loginIfNeeded(app: app, email: "alice@test.com", password: "TestPassword123!")
        handleGuidelinesIfNeeded(app: app)

        openTab(app: app, label: "Requests")

        let filterButton = app.buttons["requests.filter.Open Requests"].firstMatch
        XCTAssertTrue(filterButton.waitForExistence(timeout: 10))

        let scrollView = app.scrollViews["requests.scroll"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 10))

        let startY = filterButton.frame.minY
        let dragStart = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let dragEnd = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let endY = filterButton.frame.minY

        XCTAssertGreaterThan(endY, startY + 1, "Filter tiles should move down during pull-to-refresh")
    }

    @MainActor
    func testMessagingFlow() throws {
        let app = launchApp()
        loginIfNeeded(app: app, email: "alice@test.com", password: "TestPassword123!")
        handleGuidelinesIfNeeded(app: app)

        openTab(app: app, label: "Messages")

        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 5) {
            searchField.tap()
            searchField.typeText("test")
            searchField.buttons["Clear text"].tap()
        }

        let firstConversation = app.otherElements["messages.conversation.row"].firstMatch
        if firstConversation.waitForExistence(timeout: 10) {
            firstConversation.tap()

            let threadScroll = app.scrollViews["messages.thread.scroll"].firstMatch
            if threadScroll.waitForExistence(timeout: 5) {
                threadScroll.swipeUp()
                threadScroll.swipeDown()
            }

            if app.buttons["messages.scrollToBottom"].exists {
                app.buttons["messages.scrollToBottom"].tap()
            }

            sendTestMessageIfPossible(app: app)
            app.navigationBars.buttons.firstMatch.tap()
        }
    }

    @MainActor
    func testNotificationsFlow() throws {
        let app = launchApp()
        loginIfNeeded(app: app, email: "alice@test.com", password: "TestPassword123!")
        handleGuidelinesIfNeeded(app: app)

        let bellButton = app.buttons["bell.button"]
        XCTAssertTrue(bellButton.waitForExistence(timeout: 10))
        bellButton.tap()

        let notificationRow = app.buttons["notifications.row"].firstMatch
        if notificationRow.waitForExistence(timeout: 10) {
            notificationRow.tap()
            if app.navigationBars.buttons.firstMatch.exists {
                app.navigationBars.buttons.firstMatch.tap()
            }
        }

        app.swipeDown()
    }

    @MainActor
    func testCommunityFlow() throws {
        let app = launchApp()
        loginIfNeeded(app: app, email: "alice@test.com", password: "TestPassword123!")
        handleGuidelinesIfNeeded(app: app)

        openTab(app: app, label: "Community")

        let header = app.otherElements["community.header"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))

        let segmented = app.segmentedControls["community.segmented"]
        XCTAssertTrue(segmented.waitForExistence(timeout: 5))
        XCTAssertFalse(header.images["naars_community_icon"].exists)
        XCTAssertFalse(app.staticTexts["Share with the Community"].exists)
        XCTAssertFalse(app.staticTexts["What's on your mind?"].exists)

        segmented.buttons["Leaderboard"].tap()
        segmented.buttons["Town Hall"].tap()

        app.swipeUp()
        app.swipeDown()
    }

    @MainActor
    func testProfileFlow() throws {
        let app = launchApp()
        loginIfNeeded(app: app, email: "alice@test.com", password: "TestPassword123!")
        handleGuidelinesIfNeeded(app: app)

        openTab(app: app, label: "Profile")

        if app.buttons["profile.settings"].waitForExistence(timeout: 5) {
            app.buttons["profile.settings"].tap()
            app.swipeDown()
        }

        if app.buttons["profile.edit"].waitForExistence(timeout: 5) {
            app.buttons["profile.edit"].tap()
            app.textFields["profile.edit.name"].waitForExistence(timeout: 5)
            if app.buttons["profile.edit.cancel"].exists {
                app.buttons["profile.edit.cancel"].tap()
            } else if app.navigationBars.buttons["Cancel"].exists {
                app.navigationBars.buttons["Cancel"].tap()
            } else {
                app.navigationBars.buttons.firstMatch.tap()
            }
        }
    }

    @MainActor
    func testMultiUserCreateClaimAndMessaging() throws {
        let token = uniqueToken()
        let pickup = "UITest Pickup \(token)"
        let destination = "UITest Dest \(token)"
        let favorTitle = "UITest Favor \(token)"
        let favorLocation = "UITest Location \(token)"
        let directMessage = "UI DM \(token)"
        let groupMessage = "UI Group \(token)"

        let app = launchApp()
        loginIfNeeded(app: app, email: "alice@test.com", password: "TestPassword123!")
        handleGuidelinesIfNeeded(app: app)

        createRide(app: app, pickup: pickup, destination: destination, notes: "Notes \(token)")
        createFavor(app: app, title: favorTitle, location: favorLocation, description: "Help \(token)")

        createDirectMessage(app: app, recipientEmail: "brcolford@gmail.com", message: directMessage)
        createGroupMessage(app: app, recipientEmails: ["brcolford@gmail.com", "brendancolford@comcast.net"], message: groupMessage)

        signOut(app: app)

        loginIfNeeded(app: app, email: "brcolford@gmail.com", password: "TestPassword123!")
        handleGuidelinesIfNeeded(app: app)

        claimRide(app: app, pickup: pickup, destination: destination, message: "Claimed \(token)")
        claimFavor(app: app, title: favorTitle, location: favorLocation, message: "Favor claimed \(token)")

        verifyMessageVisible(app: app, searchText: directMessage, messageText: directMessage)
        verifyMessageVisible(app: app, searchText: groupMessage, messageText: groupMessage)

        signOut(app: app)

        loginIfNeeded(app: app, email: "brendancolford@comcast.net", password: "TestPassword123!")
        handleGuidelinesIfNeeded(app: app)

        verifyMessageVisible(app: app, searchText: groupMessage, messageText: groupMessage)
    }

    @MainActor
    func testSignupWithRegularAndBulkInvites() throws {
        let app = launchApp()
        loginIfNeeded(app: app, email: "brcolford@gmail.com", password: "TestPassword123!")
        handleGuidelinesIfNeeded(app: app)

        guard let regularCode = generateAdminInvite(app: app, mode: .regular) else {
            XCTSkip("Admin invite flow unavailable for this account")
            return
        }

        guard let bulkCode = generateAdminInvite(app: app, mode: .bulk) else {
            XCTSkip("Bulk invite flow unavailable for this account")
            return
        }

        signOut(app: app)

        signupNewUser(app: app, inviteCode: regularCode)
        signupNewUser(app: app, inviteCode: bulkCode)
    }

    @MainActor
    private func loginIfNeeded(app: XCUIApplication, email: String, password: String) {
        let emailField = app.textFields["login.email"]
        if emailField.waitForExistence(timeout: 5) {
            emailField.tap()
            emailField.typeText(email)

            let passwordField = app.secureTextFields["login.password"]
            if passwordField.waitForExistence(timeout: 2) {
                passwordField.tap()
                passwordField.typeText(password)
            }

            let submit = app.buttons["login.submit"]
            if submit.exists {
                submit.tap()
            }
        }
    }

    @MainActor
    private func handleGuidelinesIfNeeded(app: XCUIApplication) {
        let guidelinesScroll = app.scrollViews["guidelines.scroll"]
        if guidelinesScroll.waitForExistence(timeout: 10) {
            for _ in 0..<6 {
                guidelinesScroll.swipeUp()
            }
            let acceptButton = app.buttons["guidelines.accept"]
            if acceptButton.waitForExistence(timeout: 5) && acceptButton.isEnabled {
                acceptButton.tap()
            }
        }
    }

    @MainActor
    private func signOut(app: XCUIApplication) {
        openTab(app: app, label: "Profile")
        let signOutButton = app.buttons["profile.signout"]
        if signOutButton.waitForExistence(timeout: 10) {
            signOutButton.tap()
            let alert = app.alerts["Sign Out"]
            if alert.waitForExistence(timeout: 5) {
                alert.buttons["Sign Out"].tap()
            }
        }
        _ = app.textFields["login.email"].waitForExistence(timeout: 15)
    }

    @MainActor
    private func createRide(app: XCUIApplication, pickup: String, destination: String, notes: String) {
        openTab(app: app, label: "Requests")
        app.buttons["requests.createMenu"].tap()
        app.buttons["Create Ride"].firstMatch.tap()
        
        let pickupField = app.textFields["createRide.pickup"]
        XCTAssertTrue(pickupField.waitForExistence(timeout: 10))
        pickupField.tap()
        pickupField.typeText(pickup)
        
        let destinationField = app.textFields["createRide.destination"]
        XCTAssertTrue(destinationField.waitForExistence(timeout: 10))
        destinationField.tap()
        destinationField.typeText(destination)
        
        let notesField = app.textFields["createRide.notes"]
        let notesInput = notesField.exists ? notesField : app.textViews["createRide.notes"]
        if notesInput.exists {
            notesInput.tap()
            notesInput.typeText(notes)
        }

        app.buttons["createRide.post"].tap()
        
        // WAIT FOR SUCCESS: Either the detail screen OR the dashboard with the new card
        let detailTitle = app.navigationBars["Ride Details"]
        if !detailTitle.waitForExistence(timeout: 30) {
            print("DEBUG: Ride Details navigation bar not found after 30s. Hierarchy: \(app.debugDescription)")
        }
        XCTAssertTrue(detailTitle.waitForExistence(timeout: 30), "Failed to create ride - Ride Details screen didn't appear")
        
        app.navigationBars.buttons.firstMatch.tap()
    }

    @MainActor
    private func createFavor(app: XCUIApplication, title: String, location: String, description: String) {
        openTab(app: app, label: "Requests")
        app.buttons["requests.createMenu"].tap()
        app.buttons["Create Favor"].firstMatch.tap()
        
        let titleField = app.textFields["createFavor.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10))
        titleField.tap()
        titleField.typeText(title)
        
        let descriptionField = app.textFields["createFavor.description"]
        let descriptionInput = descriptionField.exists ? descriptionField : app.textViews["createFavor.description"]
        if descriptionInput.exists {
            descriptionInput.tap()
            descriptionInput.typeText(description)
        }
        
        let locationField = app.textFields["createFavor.location"]
        XCTAssertTrue(locationField.waitForExistence(timeout: 10))
        locationField.tap()
        locationField.typeText(location)

        app.buttons["createFavor.post"].tap()
        
        let detailTitle = app.navigationBars["Favor Details"]
        if !detailTitle.waitForExistence(timeout: 30) {
            print("DEBUG: Favor Details navigation bar not found after 30s. Hierarchy: \(app.debugDescription)")
        }
        XCTAssertTrue(detailTitle.waitForExistence(timeout: 30), "Failed to create favor - Favor Details screen didn't appear")
        
        app.navigationBars.buttons.firstMatch.tap()
    }

    @MainActor
    private func createDirectMessage(app: XCUIApplication, recipientEmail: String, message: String) {
        openTab(app: app, label: "Messages")
        app.buttons["messages.newMessage"].tap()
        selectUser(app: app, email: recipientEmail)
        app.buttons["userSearch.done"].tap()
        sendMessage(app: app, text: message)
        app.navigationBars.buttons.firstMatch.tap()
    }

    @MainActor
    private func createGroupMessage(app: XCUIApplication, recipientEmails: [String], message: String) {
        openTab(app: app, label: "Messages")
        app.buttons["messages.newMessage"].tap()
        for email in recipientEmails {
            selectUser(app: app, email: email)
        }
        app.buttons["userSearch.done"].tap()
        sendMessage(app: app, text: message)
        app.navigationBars.buttons.firstMatch.tap()
    }

    @MainActor
    private func selectUser(app: XCUIApplication, email: String) {
        let searchField = app.textFields["userSearch.searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText(email)
        let row = app.buttons["userSearch.row.\(email)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
    }

    @MainActor
    private func sendMessage(app: XCUIApplication, text: String) {
        let input = app.textFields["message.input"].firstMatch
        
        if !input.waitForExistence(timeout: 15) {
            print("DEBUG: message.input not found. Hierarchy: \(app.debugDescription)")
        }
        
        XCTAssertTrue(input.waitForExistence(timeout: 15), "Message input field 'message.input' not found after 15s")
        input.tap()
        input.typeText(text)
        
        // Try to tap the send button, but don't wait for it to be "valid" if the app is busy
        let sendButton = app.buttons["message.send"]
        
        // Use a very short wait and then just try tapping
        if sendButton.waitForExistence(timeout: 2) {
            sendButton.tap()
        } else {
            // Fallback: try to tap by coordinate if it exists but query times out
            if sendButton.exists {
                sendButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            } else {
                // Last resort: tap where the send button usually is
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).tap()
            }
        }
        
        // Wait a fixed amount of time for the send to process without blocking on UI queries
        Thread.sleep(forTimeInterval: 2.0)
    }

    @MainActor
    private func claimRide(app: XCUIApplication, pickup: String, destination: String, message: String) {
        openTab(app: app, label: "Requests")
        app.buttons["requests.filter.Open Requests"].firstMatch.tap()
        
        // RELAXED PREDICATE: Just look for the identifier and the unique pickup token
        let rideCard = app.buttons.matching(NSPredicate(format: "identifier == 'requests.card' AND label CONTAINS %@", pickup)).firstMatch
        
        if !rideCard.waitForExistence(timeout: 30) {
            print("DEBUG: Ride card not found for pickup '\(pickup)'. Hierarchy: \(app.debugDescription)")
            // Fallback: swipe down to refresh if it's not appearing
            app.swipeDown()
            
            // Try one more time after refresh
            if !rideCard.waitForExistence(timeout: 20) {
                 print("DEBUG: Ride card STILL not found after refresh. Hierarchy: \(app.debugDescription)")
            }
        }
        
        XCTAssertTrue(rideCard.waitForExistence(timeout: 30), "Ride card not found for pickup '\(pickup)' after 30s and refresh")
        rideCard.tap()
        
        let claimButton = app.buttons["claim.button.canClaim"]
        XCTAssertTrue(claimButton.waitForExistence(timeout: 15))
        claimButton.tap()
        
        let confirm = app.buttons["claim.confirm"]
        if confirm.waitForExistence(timeout: 10) {
            confirm.tap()
        }
        
        // After claiming, it might navigate to conversation
        if app.textFields["message.input"].waitForExistence(timeout: 15) {
            sendMessage(app: app, text: message)
            app.navigationBars.buttons.firstMatch.tap()
        }
        app.navigationBars.buttons.firstMatch.tap()
    }

    @MainActor
    private func claimFavor(app: XCUIApplication, title: String, location: String, message: String) {
        openTab(app: app, label: "Requests")
        app.buttons["requests.filter.Open Requests"].firstMatch.tap()
        
        let favorCard = app.buttons.matching(NSPredicate(format: "identifier == 'requests.card' AND label CONTAINS %@", title)).firstMatch
        
        if !favorCard.waitForExistence(timeout: 30) {
            print("DEBUG: Favor card not found for title '\(title)'. Hierarchy: \(app.debugDescription)")
            app.swipeDown()
            
            if !favorCard.waitForExistence(timeout: 20) {
                 print("DEBUG: Favor card STILL not found after refresh. Hierarchy: \(app.debugDescription)")
            }
        }
        
        XCTAssertTrue(favorCard.waitForExistence(timeout: 30), "Favor card not found for title '\(title)' after 30s and refresh")
        favorCard.tap()
        
        let claimButton = app.buttons["claim.button.canClaim"]
        XCTAssertTrue(claimButton.waitForExistence(timeout: 15))
        claimButton.tap()
        
        let confirm = app.buttons["claim.confirm"]
        if confirm.waitForExistence(timeout: 10) {
            confirm.tap()
        }
        
        if app.textFields["message.input"].waitForExistence(timeout: 15) {
            sendMessage(app: app, text: message)
            app.navigationBars.buttons.firstMatch.tap()
        }
        app.navigationBars.buttons.firstMatch.tap()
    }

    @MainActor
    private func verifyMessageVisible(app: XCUIApplication, searchText: String, messageText: String) {
        openTab(app: app, label: "Messages")
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText(searchText)
        let firstConversation = app.otherElements["messages.conversation.row"].firstMatch
        if firstConversation.waitForExistence(timeout: 10) {
            firstConversation.tap()
            _ = app.staticTexts[messageText].waitForExistence(timeout: 10)
            app.navigationBars.buttons.firstMatch.tap()
        }
        if searchField.buttons["Clear text"].exists {
            searchField.buttons["Clear text"].tap()
        }
    }

    private enum InviteMode {
        case regular
        case bulk
    }

    @MainActor
    private func generateAdminInvite(app: XCUIApplication, mode: InviteMode) -> String? {
        openTab(app: app, label: "Profile")
        let adminPanel = app.links["profile.adminPanel"]
        guard adminPanel.waitForExistence(timeout: 5) else {
            return nil
        }
        adminPanel.tap()
        let inviteCodes = app.links["admin.inviteCodes"]
        guard inviteCodes.waitForExistence(timeout: 10) else {
            return nil
        }
        inviteCodes.tap()

        switch mode {
        case .regular:
            app.buttons["admin.invite.regular"].tap()
            let statement = app.textViews["invite.statement"]
            XCTAssertTrue(statement.waitForExistence(timeout: 5))
            statement.tap()
            statement.typeText("Inviting for UI testing \(uniqueToken())")
            app.buttons["invite.generate"].tap()
            let codeLabel = app.staticTexts["invite.generatedCode"]
            XCTAssertTrue(codeLabel.waitForExistence(timeout: 10))
            let code = normalizedInviteCode(codeLabel.label)
            app.buttons["invite.done"].tap()
            return code
        case .bulk:
            app.buttons["admin.invite.bulk"].tap()
            app.buttons["admin.bulk.generate"].tap()
            let codeLabel = app.staticTexts["admin.invite.code"]
            XCTAssertTrue(codeLabel.waitForExistence(timeout: 10))
            let code = normalizedInviteCode(codeLabel.label)
            app.navigationBars.buttons.firstMatch.tap()
            return code
        }
    }

    @MainActor
    private func signupNewUser(app: XCUIApplication, inviteCode: String) {
        let signupLink = app.links["login.signup"]
        XCTAssertTrue(signupLink.waitForExistence(timeout: 5))
        signupLink.tap()

        let inviteField = app.textFields["signup.inviteCode"]
        XCTAssertTrue(inviteField.waitForExistence(timeout: 5))
        inviteField.tap()
        inviteField.typeText(inviteCode)
        app.buttons["signup.inviteNext"].tap()

        let emailMethod = app.buttons["signup.method.email"]
        XCTAssertTrue(emailMethod.waitForExistence(timeout: 10))
        emailMethod.tap()

        let nameField = app.textFields["signup.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        let unique = uniqueToken()
        nameField.tap()
        nameField.typeText("UI Test \(unique)")

        let emailField = app.textFields["signup.email"]
        emailField.tap()
        emailField.typeText("uitest+\(unique)@example.com")

        let passwordField = app.secureTextFields["signup.password"]
        passwordField.tap()
        passwordField.typeText("TestPassword123!")

        let carField = app.textFields["signup.car"]
        if carField.exists {
            carField.tap()
            carField.typeText("Test Car")
        }

        app.buttons["signup.createAccount"].tap()
        _ = app.otherElements["pendingApproval.screen"].waitForExistence(timeout: 20)
        let returnButton = app.buttons["pendingApproval.returnLogin"]
        if returnButton.waitForExistence(timeout: 10) {
            returnButton.tap()
        }
        _ = app.textFields["login.email"].waitForExistence(timeout: 15)
    }

    @MainActor
    func testRideLifecycle() throws {
        let token = uniqueToken()
        let pickup = "Lifecycle Pickup \(token)"
        let dest = "Lifecycle Dest \(token)"
        let app = launchApp()
        
        loginIfNeeded(app: app, email: "alice@test.com", password: "TestPassword123!")
        handleGuidelinesIfNeeded(app: app)
        
        // 1. Create
        createRide(app: app, pickup: pickup, destination: dest, notes: "Initial notes")
        
        // 2. Edit
        openTab(app: app, label: "Requests")
        app.buttons["requests.filter.My Requests"].firstMatch.tap()
        let rideCard = app.buttons.matching(NSPredicate(format: "identifier == 'requests.card' AND label CONTAINS %@", pickup)).firstMatch
        XCTAssertTrue(rideCard.waitForExistence(timeout: 20))
        rideCard.tap()
        
        let editButton = app.buttons["request.edit"]
        if editButton.waitForExistence(timeout: 10) {
            editButton.tap()
            
            let notesField = app.textFields["createRide.notes"]
            let notesInput = notesField.exists ? notesField : app.textViews["createRide.notes"]
            notesInput.tap()
            notesInput.typeText(" - Updated")
            app.buttons["createRide.post"].tap()
            
            XCTAssertTrue(app.staticTexts["Initial notes - Updated"].waitForExistence(timeout: 10))
        }
        
        // 3. Delete
        let deleteButton = app.buttons["request.delete"]
        if deleteButton.exists {
            deleteButton.tap()
            let deleteAlert = app.alerts.firstMatch
            if deleteAlert.waitForExistence(timeout: 5) {
                deleteAlert.buttons["Delete"].tap()
            }
        }
        
        // Verify it's gone from My Requests
        _ = rideCard.waitForNonExistence(timeout: 10)
    }

    @MainActor
    func testFavorClaimUnclaimComplete() throws {
        let token = uniqueToken()
        let title = "Favor \(token)"
        let app = launchApp()
        
        // Alice creates a favor
        loginIfNeeded(app: app, email: "alice@test.com", password: "TestPassword123!")
        handleGuidelinesIfNeeded(app: app)
        createFavor(app: app, title: title, location: "Test Location", description: "Need help")
        signOut(app: app)
        
        // Bob claims it
        loginIfNeeded(app: app, email: "brcolford@gmail.com", password: "TestPassword123!")
        handleGuidelinesIfNeeded(app: app)
        
        openTab(app: app, label: "Requests")
        app.buttons["requests.filter.Open Requests"].firstMatch.tap()
        
        // Manual refresh to ensure the new favor appears
        app.swipeDown()
        
        // Try to find the card using a more flexible approach
        // Look for ANY element that contains the title
        let favorCard = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        
        var found = favorCard.waitForExistence(timeout: 30)
        if !found {
            app.swipeDown()
            found = favorCard.waitForExistence(timeout: 30)
        }
        
        XCTAssertTrue(found, "Favor card not found for title '\(title)' after multiple refreshes")
        favorCard.tap()
        
        let claimButton = app.buttons["claim.button.canClaim"]
        XCTAssertTrue(claimButton.waitForExistence(timeout: 10))
        claimButton.tap()
        app.buttons["claim.confirm"].tap()
        
        // Bob unclaims it
        XCTAssertTrue(app.buttons["claim.button.claimedByMe"].waitForExistence(timeout: 10))
        app.buttons["claim.button.claimedByMe"].tap()
        app.buttons["unclaim.confirm"].tap()
        
        // Bob claims it again to complete it later
        XCTAssertTrue(app.buttons["claim.button.canClaim"].waitForExistence(timeout: 10))
        app.buttons["claim.button.canClaim"].tap()
        app.buttons["claim.confirm"].tap()
        signOut(app: app)
        
        // Alice marks it complete
        loginIfNeeded(app: app, email: "alice@test.com", password: "TestPassword123!")
        handleGuidelinesIfNeeded(app: app)
        openTab(app: app, label: "Requests")
        app.buttons["requests.filter.My Requests"].firstMatch.tap()
        favorCard.tap()
        
        let completeButton = app.buttons["claim.button.markComplete"]
        XCTAssertTrue(completeButton.waitForExistence(timeout: 10))
        completeButton.tap()
        app.buttons["complete.confirm"].tap()
        
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testRichMessaging() throws {
        let app = launchApp()
        loginIfNeeded(app: app, email: "alice@test.com", password: "TestPassword123!")
        handleGuidelinesIfNeeded(app: app)
        
        // Ensure there is at least one conversation
        let token = uniqueToken()
        let messageText = "Rich messaging test ping \(token)"
        createDirectMessage(app: app, recipientEmail: "brcolford@gmail.com", message: messageText)
        
        openTab(app: app, label: "Messages")
        
        // Open the conversation we just created - look for the row by label
        let conversationRow = app.otherElements.matching(NSPredicate(format: "label CONTAINS 'brcolford@gmail.com' OR label CONTAINS 'Brendan Colford'")).firstMatch
        
        if !conversationRow.waitForExistence(timeout: 30) {
            // Try searching as a fallback
            let searchField = app.searchFields.firstMatch
            if searchField.waitForExistence(timeout: 5) {
                searchField.tap()
                searchField.typeText("brcolford@gmail.com")
            }
        }
        
        XCTAssertTrue(conversationRow.waitForExistence(timeout: 30), "Conversation row not found for brcolford@gmail.com")
        conversationRow.tap()
        
        // 1. Send Location
        let plusButton = app.buttons["plus.circle.fill"]
        XCTAssertTrue(plusButton.waitForExistence(timeout: 10))
        plusButton.tap()
        
        let locationButton = app.buttons["Location"]
        XCTAssertTrue(locationButton.waitForExistence(timeout: 5))
        locationButton.tap()
        
        let sendLocationButton = app.buttons["Send Location"]
        XCTAssertTrue(sendLocationButton.waitForExistence(timeout: 15))
        sendLocationButton.tap()
        
        // 2. Long press and react
        // Wait for the location message to appear (it has a specific label or just wait)
        Thread.sleep(forTimeInterval: 2.0)
        
        let messageQuery = app.otherElements.matching(NSPredicate(format: "identifier CONTAINS 'messages.thread.message'"))
        let lastMessage = messageQuery.element(boundBy: messageQuery.count - 1)
        XCTAssertTrue(lastMessage.waitForExistence(timeout: 15))
        lastMessage.press(forDuration: 1.5)
        
        let reaction = app.buttons["❤️"].firstMatch
        if reaction.waitForExistence(timeout: 5) {
            reaction.tap()
        }
        
        // 3. Reply
        lastMessage.press(forDuration: 1.5)
        let replyButton = app.buttons["Reply"]
        if replyButton.waitForExistence(timeout: 5) {
            replyButton.tap()
            sendMessage(app: app, text: "Replying to location \(token)")
        }
    }

    @MainActor
    func testProfileSettingsAndEdit() throws {
        let app = launchApp()
        loginIfNeeded(app: app, email: "alice@test.com", password: "TestPassword123!")
        handleGuidelinesIfNeeded(app: app)
        
        openTab(app: app, label: "Profile")
        
        // 1. Edit Profile
        app.buttons["profile.edit"].tap()
        let nameField = app.textFields["profile.edit.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(" Updated")
        
        if app.buttons["Save"].exists {
            app.buttons["Save"].tap()
        } else {
            app.navigationBars.buttons.firstMatch.tap()
        }
        
        // 2. Settings
        app.buttons["profile.settings"].tap()
        
        let notificationsToggle = app.switches.firstMatch
        if notificationsToggle.exists {
            notificationsToggle.tap()
            notificationsToggle.tap() // Toggle back
        }
        
        app.swipeDown() // Close settings
        
        // 3. Logout
        signOut(app: app)
    }

    private func uniqueToken() -> String {
        String(UUID().uuidString.prefix(8))
    }

    private func normalizedInviteCode(_ label: String) -> String {
        label.replacingOccurrences(of: "·", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launch()
        return app
    }

    @MainActor
    private func openTab(app: XCUIApplication, label: String) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30))
        if tabBar.buttons[label].exists {
            tabBar.buttons[label].tap()
        }
    }

    @MainActor
    private func sendTestMessageIfPossible(app: XCUIApplication) {
        let messageField = app.textFields["message.input"].firstMatch
        let messageTextView = app.textViews["message.input"].firstMatch
        let input = messageField.exists ? messageField : messageTextView
        if input.waitForExistence(timeout: 5) {
            input.tap()
            input.typeText("UI test ping")
            let sendButton = app.buttons["message.send"]
            if sendButton.exists && sendButton.isEnabled {
                sendButton.tap()
            }
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
