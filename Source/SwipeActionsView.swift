//
//  SwipeActionsView.swift
//
//  Created by Jeremy Koch
//  Copyright © 2017 Jeremy Koch. All rights reserved.
//

import UIKit

protocol SwipeActionsViewDelegate: class {
    func swipeActionsView(_ swipeActionsView: SwipeActionsView, didSelect action: SwipeAction)
}

class SwipeActionsView: UIView {
    weak var delegate: SwipeActionsViewDelegate?
    
    let transitionLayout: SwipeTransitionLayout
    var layoutContext: ActionsViewLayoutContext
    
    var feedbackGenerator: SwipeFeedback
    
    var expansionAnimator: SwipeAnimator?
    
    var expansionDelegate: SwipeExpanding? {
        return options.expansionDelegate ?? (expandableAction?.hasBackgroundColor == false ? ScaleAndAlphaExpansion.default : nil)
    }

    weak var safeAreaInsetView: UIView?
    let orientation: SwipeActionsOrientation
    let actions: [SwipeAction]
    let options: SwipeOptions

    var views: [UIView] = []
    
//    var minimumButtonWidth: CGFloat = 0
    var maximumImageHeight: CGFloat {
        return actions.reduce(0, { initial, next in max(initial, next.image?.size.height ?? 0) })
    }
    
    var safeAreaMargin: CGFloat {
        guard #available(iOS 11, *) else { return 0 }
        guard let scrollView = self.safeAreaInsetView else { return 0 }
        return orientation == .left ? scrollView.safeAreaInsets.left : scrollView.safeAreaInsets.right
    }

    var visibleWidth: CGFloat = 0 {
        didSet {
            // If necessary, adjust for safe areas
            visibleWidth = max(0, visibleWidth - safeAreaMargin)

            let preLayoutVisibleWidths = transitionLayout.visibleWidthsForViews(with: layoutContext)

            layoutContext = ActionsViewLayoutContext.newContext(for: self)
            
            transitionLayout.container(view: self, didChangeVisibleWidthWithContext: layoutContext)
            
            setNeedsLayout()
            layoutIfNeeded()
            
            notifyVisibleWidthChanged(oldWidths: preLayoutVisibleWidths,
                                      newWidths: transitionLayout.visibleWidthsForViews(with: layoutContext))
        }
    }

    var preferredWidth: CGFloat {
        return self.views.reduce(0) { $0 + $1.frame.width } + safeAreaMargin
    }

    var contentSize: CGSize {
        if options.expansionStyle?.elasticOverscroll != true || visibleWidth < preferredWidth {
            return CGSize(width: visibleWidth, height: bounds.height)
        } else {
            let scrollRatio = max(0, visibleWidth - preferredWidth)
            return CGSize(width: preferredWidth + (scrollRatio * 0.25), height: bounds.height)
        }
    }
    
    private(set) var expanded: Bool = false
    
    var expandableAction: SwipeAction? {
        return options.expansionStyle != nil ? actions.last : nil
    }
    
    init(contentEdgeInsets: UIEdgeInsets,
         maxSize: CGSize,
         safeAreaInsetView: UIView,
         options: SwipeOptions,
         orientation: SwipeActionsOrientation,
         actions: [SwipeAction]) {
        
        self.safeAreaInsetView = safeAreaInsetView
        self.options = options
        self.orientation = orientation
        self.actions = actions.reversed()
        
        switch options.transitionStyle {
        case .border:
            transitionLayout = BorderTransitionLayout()
        case .reveal:
            transitionLayout = RevealTransitionLayout()
        default:
            transitionLayout = DragTransitionLayout()
        }
        
        self.layoutContext = ActionsViewLayoutContext(numberOfActions: actions.count, orientation: orientation, widths: self.views.map { $0.frame.width })
        
        feedbackGenerator = SwipeFeedback(style: .light)
        feedbackGenerator.prepare()
        
        super.init(frame: .zero)
        
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        

    #if canImport(Combine)
        if let backgroundColor = options.backgroundColor {
            self.backgroundColor = backgroundColor
        }
        else if #available(iOS 13.0, *) {
            backgroundColor = UIColor.systemGray5
        } else {
            backgroundColor = #colorLiteral(red: 0.7803494334, green: 0.7761332393, blue: 0.7967314124, alpha: 1)
        }
    #else
        if let backgroundColor = options.backgroundColor {
            self.backgroundColor = backgroundColor
        }
        else {
            backgroundColor = #colorLiteral(red: 0.7803494334, green: 0.7761332393, blue: 0.7967314124, alpha: 1)
        }
    #endif
        
        views = addViews(for: self.actions, withMaximum: maxSize, contentEdgeInsets: contentEdgeInsets)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func addViews(for actions: [SwipeAction], withMaximum size: CGSize, contentEdgeInsets: UIEdgeInsets) -> [UIView] {
        let views: [UIView] = actions.map({ action in
            let actionView: UIView = {
                let customView = action.customView
                customView?.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(actionTapped(_:))))
                return customView
            }() ?? {
                let actionButton = SwipeActionButton(action: action)
                actionButton.addTarget(self, action: #selector(actionTapped(view:)), for: .touchUpInside)
                actionButton.autoresizingMask = [.flexibleHeight, orientation == .right ? .flexibleRightMargin : .flexibleLeftMargin]
                actionButton.spacing = options.buttonSpacing ?? 8
                actionButton.contentEdgeInsets = buttonEdgeInsets(fromOptions: options)
                return actionButton
            }()

            return actionView
        })
        
        let maximum = options.maximumButtonWidth ?? (size.width - 30) / CGFloat(actions.count)
        let minimum = options.minimumButtonWidth ?? min(maximum, 74)
        let minimumButtonWidth = views.reduce(minimum, { initial, next in
            if let button = next as? SwipeActionButton {
                return max(initial, button.preferredWidth(maximum: maximum))
            }

            return max(initial, initial)
        })
        
        views.enumerated().forEach { (index, view) in
            let action = actions[index]
            let frame = CGRect(origin: .zero, size: CGSize(width: bounds.width, height: bounds.height))
            let wrapperView = SwipeActionButtonWrapperView(frame: frame, action: action, orientation: orientation, view: {
                guard let button = view as? SwipeActionButton else {
                    return view
                }

                let view = UIView()
                view.translatesAutoresizingMaskIntoConstraints = false
                view.widthAnchor.constraint(equalToConstant: minimumButtonWidth).isActive = true
                view.addSubview(button)
                button.frame = .init(x: 0, y: 0, width: minimumButtonWidth, height: frame.height)
                return view
            }())

            wrapperView.translatesAutoresizingMaskIntoConstraints = false
            
            if let effect = action.backgroundEffect {
                let effectView = UIVisualEffectView(effect: effect)
                effectView.frame = wrapperView.frame
                effectView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
                effectView.contentView.addSubview(wrapperView)
                addSubview(effectView)
            } else {
                addSubview(wrapperView)
            }

            if let actionButton = view as? SwipeActionButton {
                actionButton.maximumImageHeight = maximumImageHeight
                actionButton.verticalAlignment = options.buttonVerticalAlignment
                actionButton.shouldHighlight = action.hasBackgroundColor
            }

            wrapperView.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
            wrapperView.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
            
            let topConstraint = wrapperView.topAnchor.constraint(equalTo: topAnchor, constant: contentEdgeInsets.top)
            topConstraint.priority = contentEdgeInsets.top == 0 ? .required : .defaultHigh
            topConstraint.isActive = true
            
            let bottomConstraint = wrapperView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1 * contentEdgeInsets.bottom)
            bottomConstraint.priority = contentEdgeInsets.bottom == 0 ? .required : .defaultHigh
            bottomConstraint.isActive = true
            
            if contentEdgeInsets != .zero {
                let heightConstraint = wrapperView.heightAnchor.constraint(greaterThanOrEqualToConstant: view.intrinsicContentSize.height)
                heightConstraint.priority = .required
                heightConstraint.isActive = true
            }
        }

        return views
    }

    @objc func actionTapped(view: UIView) {
        guard let index = views.firstIndex(of: view) else { return }

        delegate?.swipeActionsView(self, didSelect: actions[index])
    }

    @objc func actionTapped(_ sender: UITapGestureRecognizer) {
        guard case .ended = sender.state else {
            return
        }

        if let view = sender.view {
            self.actionTapped(view: view)
            return
        }
        
        for view in self.views {
            let touchPoint = sender.location(in: view)
            if view.frame.contains(touchPoint) {
                self.actionTapped(view: view)
                break
            }
        }
    }
    
    func buttonEdgeInsets(fromOptions options: SwipeOptions) -> UIEdgeInsets {
        let padding = options.buttonPadding ?? 8
        return UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)
    }
    
    func setExpanded(expanded: Bool, feedback: Bool = false) {
        guard self.expanded != expanded else { return }
        
        self.expanded = expanded
        
        if feedback {
            feedbackGenerator.impactOccurred()
            feedbackGenerator.prepare()
        }
        
        let timingParameters = expansionDelegate?.animationTimingParameters(views: views.reversed(), expanding: expanded)
        
        if expansionAnimator?.isRunning == true {
            expansionAnimator?.stopAnimation(true)
        }
        
        if #available(iOS 10, *) {
            expansionAnimator = UIViewPropertyAnimator(duration: timingParameters?.duration ?? 0.6, dampingRatio: 1.0)
        } else {
            expansionAnimator = UIViewSpringAnimator(duration: timingParameters?.duration ?? 0.6,
                                                     damping: 1.0,
                                                     initialVelocity: 1.0)
        }
        
        expansionAnimator?.addAnimations {
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
        
        expansionAnimator?.startAnimation(afterDelay: timingParameters?.delay ?? 0)
        
        notifyExpansion(expanded: expanded)
    }
    
    func notifyVisibleWidthChanged(oldWidths: [CGFloat], newWidths: [CGFloat]) {
        DispatchQueue.main.async {
            oldWidths.enumerated().forEach { index, oldWidth in
                let view = self.views[index]
                let newWidth = newWidths[index]
                if oldWidth != newWidth {
                    let context = SwipeActionTransitioningContext(actionIdentifier: self.actions[index].identifier,
                                                                  view: self.views[index],
                                                                  newPercentVisible: newWidth / view.frame.width,
                                                                  oldPercentVisible: oldWidth / view.frame.width,
                                                                  wrapperView: self.subviews[index])
                    
                    self.actions[index].transitionDelegate?.didTransition(with: context)
                }
            }
        }
    }
    
    func notifyExpansion(expanded: Bool) {
        guard let expandedView = views.last else { return }

        expansionDelegate?.actionButton(expandedView, didChange: expanded, otherActionViews: views.dropLast().reversed())
    }
    
    func createDeletionMask() -> UIView {
        let mask = UIView(frame: CGRect(x: min(0, frame.minX), y: 0, width: bounds.width * 2, height: bounds.height))
        mask.backgroundColor = UIColor.white
        return mask
    }

    var lastFrame: CGRect?
    override func layoutSubviews() {
        super.layoutSubviews()
        
        for subview in subviews.enumerated() {
            transitionLayout.layout(view: subview.element, atIndex: subview.offset, with: layoutContext)
        }
        
        if expanded {
            subviews.last?.frame.origin.x = 0 + bounds.origin.x
        }
    }
}

class SwipeActionButtonWrapperView: UIView {
//    let contentRect: CGRect
    var actionBackgroundColor: UIColor?
    
    init(frame: CGRect, action: SwipeAction, orientation: SwipeActionsOrientation, view: UIView) {
        super.init(frame: frame)
        self.addSubview(view)
        view.topAnchor.constraint(equalTo: topAnchor).isActive = true
        view.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true

        switch orientation {
        case .left:
            view.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
        case .right:
            view.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
        }
        
        configureBackgroundColor(with: action)
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        if let actionBackgroundColor = self.actionBackgroundColor, let context = UIGraphicsGetCurrentContext() {
            actionBackgroundColor.setFill()
            context.fill(rect);
        }
    }
    
    func configureBackgroundColor(with action: SwipeAction) {
        guard action.hasBackgroundColor else {
            isOpaque = false
            return
        }
        
        if let backgroundColor = action.backgroundColor {
            actionBackgroundColor = backgroundColor
        } else {
            switch action.style {
            case .destructive:
            #if canImport(Combine)
                if #available(iOS 13.0, *) {
                    actionBackgroundColor = UIColor.systemRed
                } else {
                    actionBackgroundColor = #colorLiteral(red: 1, green: 0.2352941176, blue: 0.1882352941, alpha: 1)
                }
            #else
                actionBackgroundColor = #colorLiteral(red: 1, green: 0.2352941176, blue: 0.1882352941, alpha: 1)
            #endif
            default:
            #if canImport(Combine)
                if #available(iOS 13.0, *) {
                    actionBackgroundColor = UIColor.systemGray3
                } else {
                    actionBackgroundColor = #colorLiteral(red: 0.7803494334, green: 0.7761332393, blue: 0.7967314124, alpha: 1)
                }
            #else
                actionBackgroundColor = #colorLiteral(red: 0.7803494334, green: 0.7761332393, blue: 0.7967314124, alpha: 1)
            #endif
            }
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
