//
// This source file is part of swift-parsers, an open source project by Wayfair
//
// Copyright (c) 2019 Wayfair, LLC.
// Licensed under the 2-Clause BSD License
//
// See LICENSE.md for license information
//

struct Person { let firstName, lastName: String }

struct ContactCard {
    let person: Person

    let phoneNumber: String
}

let exampleData = """
McPerson,John Jr.;555-123-9090
St. Personson,Alicia;555-789-1111
"""

import Parsers
import Prelude

let parseName = noneOf(",;\n").zeroOrMore.map { String.init($0) }

let parsePerson = liftA(flip(Person.init), parseName <* string(","), parseName)

let parsePhone = oneOf("1234567890-").repeated(12).map { String.init($0) }

let parseContactCard = liftA(
    ContactCard.init,
    parsePerson <* string(";"),
    parsePhone <* string("\n").zeroOrMore
)

dump(
    try parseContactCard.repeated(2).run(exampleData)
)
