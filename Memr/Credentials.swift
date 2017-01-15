//
//  Credentials.swift
//  PokeFace
//
//  Created by Timotius Sitorus on 4/3/16.
//  Copyright © 2016 Timotius Sitorus. All rights reserved.
//

import Foundation

let clarifaiClientID = "_5BweF4mMShnzyjAQZISYoLyOPwQ02uwQzQerXcb"
let clarifaiClientSecret = "2mBseWtWstYBLuKj8KKmBrRF5uebnd4Vk5eMSTI2"


@objc class Credentials : NSObject {
    class func clientID() -> String { return clarifaiClientID }
    class func clientSecret() -> String { return clarifaiClientSecret }
}