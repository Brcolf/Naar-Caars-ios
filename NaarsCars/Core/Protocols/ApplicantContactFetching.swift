//
//  ApplicantContactFetching.swift
//  NaarsCars
//
//  Narrow read of an applicant's email and phone for platform admins
//

import Foundation

/// An applicant's contact details. Only a platform admin can read them (`profiles_select_admin`);
/// community admins never see them.
struct ApplicantContact: Decodable, Equatable, Sendable {
    let email: String?
    let phoneNumber: String?

    enum CodingKeys: String, CodingKey {
        case email
        case phoneNumber = "phone_number"
    }
}

protocol ApplicantContactFetching: AnyObject {
    func fetchApplicantContact(userId: UUID) async throws -> ApplicantContact
}
