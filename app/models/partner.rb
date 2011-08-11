# == Schema Information
#
# Table name: partners
#
#  id               :integer(4)      not null, primary key
#  name             :string(255)
#  url              :string(255)
#  country          :string(255)
#  time             :integer(4)
#  repeat_any_other :boolean(1)      default(FALSE)
#  subheader        :string(255)
#  created_at       :datetime
#  updated_at       :datetime
#  place            :string(255)     default("right")
#  long_name        :string(255)
#

class Partner < ActiveRecord::Base
  has_one :description, :as => :describable

  scope :country, lambda {|country| where(:country => country) }
  scope :place, lambda {|position| where(:place => position) }
  scope :left, where(:place => "left")
  scope :right, where(:place => "right")
  scope :unique, group("name")
  scope :include_descriptions, includes(:description)
  
  accepts_nested_attributes_for :description

  ##
  # TODO: Handle the case when a partner has strange characters in the name.
  #       It's probably easiest to add a new attribute 'slug' to partners that
  #       holds a url suitable name.
  #
  def self.find_by_slug(name)
    find_by_name(name.to_s.downcase)
  end

  def description?
    self.description
  end

  def name_or_long_name
    self.long_name ? self.long_name : self.name
  end
  
  def logo
    "/images/partners/#{name.downcase}.png"
  end
  
  def link
    description && !description.content.blank? ? "/partners/#{name.downcase}" : url
  end
end